import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber

/// Deterministic serialization backend for a Fiber tree. Browser adapters can
/// consume the same tree/mutations without introducing another renderer.
package struct StaticHTMLFiberRenderer: FiberRenderer {
  package typealias Output = String
  package let rootTag: String
  /// Tag of the placeholder elements the browser host writes for subtrees it already holds. The serializer writes it
  /// like any other element.
  package static let keepTag = "keep"
  /// How many elements may nest before the output stops nesting them. An element opened below that depth is closed
  /// at once and its children follow it as its siblings, which is the tree an HTML parser builds anyway (both
  /// Chromium and WebKit stop nesting at 512 and attach what comes next to the last open element's parent). Written
  /// that way the parser does not see the depth: Chromium's cost per start tag grows with the depth of the stack of
  /// open elements, so a few thousand nested `div`s took seconds to parse. Nil keeps every level nested.
  package let maxElementDepth: Int?
  package init(rootTag: String = "body", maxElementDepth: Int? = nil) {
    self.rootTag = rootTag
    self.maxElementDepth = maxElementDepth
  }

  @MainActor package func renderTree<V: View>(_ view: V) -> FiberTree { FiberTree(view, deferLazyCollections: false) }
  @MainActor package func render<V: View>(_ view: V) -> String { renderNode(renderTree(view).root.renderNode) }

  @MainActor package func renderHTML<V: View>(_ view: V) -> String { render(view) }

  /// Serializes an already-reconciled Fiber render node. Browser adapters use
  /// this backend-neutral entry point when committing a snapshot to the DOM.
  package func renderNode(_ node: _RenderNode) -> String {
    withRenderedUTF8(node) { String(htmlUTF8: $0) }
  }

  /// Same output as `renderNode` as UTF-8 bytes.
  package func renderNodeUTF8(_ node: _RenderNode) -> [UInt8] {
    withRenderedUTF8(node) { Array($0) }
  }

  /// Same output as `renderNode`, lent to `body` as the bytes the serialization wrote: the browser host copies them
  /// straight into its transfer buffer, without a `String` or an `Array` in between. They are valid only inside `body`.
  package func withRenderedUTF8<Result>(_ node: _RenderNode, _ body: (UnsafeBufferPointer<UInt8>) -> Result) -> Result {
    // A publication is about as long as the one before it: start with room for that (an unusually large one is not
    // reserved again for every small serialization after it).
    var state = HTMLWriteState(capacity: min(Self.sizeHint &+ Self.sizeHint / 8, 1 << 21))
    defer { state.release() }
    write(node, into: &state)
    Self.sizeHint = state.bytes.count
    return body(UnsafeBufferPointer(start: UnsafePointer(state.bytes.base), count: state.bytes.count))
  }

  /// The size of the last serialization, to reserve the next one's buffer from. Only a hint: a stale value costs a
  /// regrowth, never correctness.
  nonisolated(unsafe) private static var sizeHint = 4096

  // MARK: Tags

  // Immutable and shared by every serialization call. Only a tag with a non-ASCII byte in it (whose lowercased form
  // could still be one of these) looks the names up here; the others are told apart by their bytes.
  private static let voidTags: Set<String> = [
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
    "meta", "param", "source", "track", "wbr"
  ]

  /// Whether `tag` (the `length` bytes at `bytes`) is a void tag, compared without case. Every such name is at most 8
  /// ASCII bytes: they are packed with their length into one word and looked up in a switch.
  static func isVoidTag(_ tag: String, bytes: UnsafePointer<UInt8>, length: Int) -> Bool {
    if length > 8 || length == 0 { return false }
    var key: UInt64 = 0
    var index = 0
    while index < length {
      var byte = bytes[index]
      if byte >= 0x80 { return slowIsVoidTag(tag) }
      if byte &- 65 < 26 { byte |= 0x20 }
      key |= UInt64(byte) << UInt64(8 &* index)
      index &+= 1
    }
    switch key | UInt64(length) << 56 {
    case 0x0400_0000_6165_7261,   // area
         0x0400_0000_6573_6162,   // base
         0x0200_0000_0000_7262,   // br
         0x0300_0000_006c_6f63,   // col
         0x0500_0064_6562_6d65,   // embed
         0x0200_0000_0000_7268,   // hr
         0x0300_0000_0067_6d69,   // img
         0x0500_0074_7570_6e69,   // input
         0x0400_0000_6b6e_696c,   // link
         0x0400_0000_6174_656d,   // meta
         0x0500_006d_6172_6170,   // param
         0x0600_6563_7275_6f73,   // source
         0x0500_006b_6361_7274,   // track
         0x0300_0000_0072_6277:   // wbr
      return true
    default: return false
    }
  }

  @inline(never)
  private static func slowIsVoidTag(_ tag: String) -> Bool {
    voidTags.contains(tag.lowercased())
  }

  // MARK: Walking the tree

  // One growing byte buffer for the whole tree: no per-node String, no `map { }.joined()` copies at every depth, no
  // per-value FFI for escaping.
  //
  // A loop over an explicit stack rather than a recursion: a view hierarchy hundreds of levels deep is a tree as
  // deep, and one WebAssembly frame per level of it is more than a WebKit Worker's stack holds.
  private func write(_ root: _RenderNode, into state: inout HTMLWriteState) {
    open(root, into: &state)
    while state.frameCount > 0 {
      let top = state.frameCount - 1
      if state.frames[top].next < state.frames[top].children.count {
        let child = state.frames[top].children[state.frames[top].next]
        state.frames[top].next += 1
        open(child, into: &state)
      } else {
        let frame = state.popFrame()
        if frame.isElement && !frame.flat { state.depth -= 1 }
        close(frame, into: &state)
      }
    }
  }

  /// Writes what comes before a node's children. A node with children is left open on the stack.
  private func open(_ node: _RenderNode, into state: inout HTMLWriteState) {
    switch node.kind {
    case .empty: return
    case .fragment:
      state.pushFrame(HTMLWriteFrame(node: node, children: node.children, start: state.bytes.count, tagLength: -1, writesChildren: true))
    case .text: writeText(node, into: &state)
    case .element(let tag): openElement(node, tag: tag, into: &state)
    }
  }

  private func writeText(_ node: _RenderNode, into state: inout HTMLWriteState) {
    let plain = node.attributes.isEmpty && node.styles.isEmpty && node.classes.isEmpty && node.events.isEmpty
    if !plain {
      state.bytes.append("<span")
      var info = AttributeInfo()
      writeAttributes(of: node, isElement: false, into: &state, info: &info)
      state.bytes.append(Self.greaterThan)
    }
    state.bytes.appendEscaped(node.text ?? "")
    if !plain { state.bytes.append("</span>") }
  }

  private func openElement(_ node: _RenderNode, tag: String, into state: inout HTMLWriteState) {
    let start = state.bytes.count
    state.bytes.append(Self.lessThan)
    state.bytes.append(utf8: tag)
    let tagLength = state.bytes.count - start - 1
    var info = AttributeInfo()
    writeAttributes(of: node, isElement: true, into: &state, info: &info)
    state.bytes.append(Self.greaterThan)
    let writesChildren = !Self.isVoidTag(tag, bytes: state.bytes.base + start + 1, length: tagLength)
    var flat = false
    if writesChildren, let maxElementDepth { flat = state.depth >= maxElementDepth }
    if flat {
      state.bytes.append("</")
      state.bytes.append(copyOf: start + 1, count: tagLength)
      state.bytes.append(Self.greaterThan)
    }
    state.pushFrame(HTMLWriteFrame(node: node, children: writesChildren ? node.children : [], start: start, tagLength: tagLength, flat: flat, writesChildren: writesChildren))
    if !flat { state.depth += 1 }
  }

  /// Writes what comes after a node's children.
  private func close(_ frame: HTMLWriteFrame, into state: inout HTMLWriteState) {
    guard frame.isElement else { return }
    if frame.writesChildren && !frame.flat {
      state.bytes.append("</")
      state.bytes.append(copyOf: frame.start + 1, count: frame.tagLength)
      state.bytes.append(Self.greaterThan)
    }
  }

  // MARK: Attributes

  /// What `writeAttributes` learned about a node's attributes on the way.
  struct AttributeInfo {
    /// An attribute the host mutates on its own (typed text, tab selection, lazy windows...), so the binary encoder
    /// does not take the element's state for the host's. Tab selection is applied client-side before Swift answers
    /// (panels flip `data-tab-hidden`, tab buttons `aria-selected`), and popovers toggle `data-open`.
    var hostOwned = false
  }

  private static let classFlag: UInt8 = 1
  private static let styleFlag: UInt8 = 2
  private static let layoutFlag: UInt8 = 4
  private static let hostOwnedFlag: UInt8 = 8

  @inline(__always)
  private static func same(_ bytes: UnsafePointer<UInt8>, _ literal: StaticString) -> Bool {
    var index = 0
    let length = literal.utf8CodeUnitCount
    while index < length {
      if bytes[index] != literal.utf8Start[index] { return false }
      index &+= 1
    }
    return true
  }

  /// Which of the attributes this writer looks for the name at `bytes` is, told apart by length first and then by
  /// bytes. `role` is the one that depends on its value (`tab`), which the caller checks.
  private static func attributeFlags(_ bytes: UnsafePointer<UInt8>, length: Int) -> UInt8 {
    switch length {
    case 4: return same(bytes, "role") ? roleFlag : 0
    case 5:
      if same(bytes, "class") { return classFlag }
      return same(bytes, "style") ? styleFlag : 0
    case 7: return same(bytes, "popover") ? hostOwnedFlag : 0
    case 14:
      return same(bytes, "data-tab-panel") ? hostOwnedFlag : 0
    case 15: return same(bytes, "contenteditable") ? hostOwnedFlag : 0
    case 16: return same(bytes, "data-layout-kind") ? layoutFlag : 0
    case 18: return same(bytes, "data-timeline-view") || same(bytes, "data-mesh-gradient") ? hostOwnedFlag : 0
    case 19: return same(bytes, "data-keep-secure-id") || same(bytes, "data-web-mount-flag") ? hostOwnedFlag : 0
    case 20: return same(bytes, "data-keep-lazy-index") ? hostOwnedFlag : 0
    default: return 0
    }
  }

  private static let roleFlag: UInt8 = 16

  /// Lifecycle, task, and geometry callbacks are coordinated by Fiber/host adapters rather than DOM event listeners.
  /// Their names stay out of serialized HTML while ordinary browser events are written.
  private static func isInternalEvent(_ name: String) -> Bool {
    name == "appear" || name == "disappear" || name == "task" || name == "geometry" || name == "geometryChange"
      || name == "openURL" || name == "presentation-dismiss" || name == "web-navigation" || name == "web-external-link"
  }

  /// Writes ` name="value"` for every attribute in name order (see `assembleAttributes`).
  private func writeAttributes(of node: _RenderNode, isElement: Bool, into state: inout HTMLWriteState, info: inout AttributeInfo) {
    var sink = HTMLAttributeText()
    Self.assembleAttributes(of: node, isElement: isElement, into: &state, info: &info, sink: &sink)
  }

  /// Hands every attribute of `node` to `sink` in name order, with the value it is written with: the node's own
  /// attributes, `class` joined from its class list (with `passthrough` for a hit-transparent layout container), `style`
  /// joined from its declarations, and an attribute for each event the page listens to. The HTML serializer writes them
  /// as markup and the binary encoder as (name, value) pairs, so the names, the values and their order are decided in
  /// this one place. The names are copied once into a scratch arena and sorted there as bytes (a name with a non-ASCII
  /// byte is ordered as the `String` it is, which is not bytewise); the values are read from the node's own storage.
  /// `class` and `style` reach the sink piece by piece instead of being joined into temporary strings first.
  static func assembleAttributes<Sink: HTMLAttributeSink>(of node: _RenderNode, isElement: Bool, into state: inout HTMLWriteState, info: inout AttributeInfo, sink: inout Sink) {
    let attributeArray = node.attributes._entries
    let classes = node.classes
    let styleArray = node.styles._entries
    let events = node.events
    if attributeArray.isEmpty && classes.isEmpty && styleArray.isEmpty && events.isEmpty { return }
    state.resetAttributes()
    // The pairs are read in place: copying one out of the array would retain both strings.
    attributeArray.withUnsafeBufferPointer { attributes in
      styleArray.withUnsafeBufferPointer { styles in
        assembleAttributes(of: node, isElement: isElement, attributes: attributes, styles: styles, classes: classes, events: events, into: &state, info: &info, sink: &sink)
      }
    }
  }

  private static func assembleAttributes<Sink: HTMLAttributeSink>(
    of node: _RenderNode, isElement: Bool, attributes: UnsafeBufferPointer<(key: String, value: String)>, styles: UnsafeBufferPointer<(key: String, value: String)>,
    classes: [String], events: _NodeEvents, into state: inout HTMLWriteState, info: inout AttributeInfo, sink: inout Sink
  ) {

    var classItem = -1, styleItem = -1
    var layout = false
    var index = 0
    while index < attributes.count {
      let item = state.addItem(key: attributes[index].key, kind: .text, source: index)
      let flags = Self.attributeFlags(state.keyBytes(state.items[item]), length: state.items[item].keyLength)
      if flags != 0 {
        if flags == Self.classFlag { classItem = item }
        else if flags == Self.styleFlag { styleItem = item }
        else if flags == Self.layoutFlag { layout = true }
        else if flags == Self.hostOwnedFlag { info.hostOwned = true }
        else if attributes[index].value == "tab" { info.hostOwned = true }   // role
      }
      index += 1
    }
    // SwiftUI hit testing: pure layout containers let pointer events through.
    let passthrough = isElement && layout && node._isHitTransparent
    if passthrough || !classes.isEmpty {
      if classItem >= 0 { state.items[classItem].kind = .classes } else { _ = state.addItem(key: "class", kind: .classes, source: -1) }
    }
    let hasStyles = !styles.isEmpty
    if hasStyles {
      if styleItem >= 0 { state.items[styleItem].kind = .style } else { _ = state.addItem(key: "style", kind: .style, source: -1) }
    }
    for (name, event) in events where !Self.isInternalEvent(name) {
      let item = state.addEventKey(name: name)
      state.items[item].kind = .event
      state.items[item].source = state.eventValues.count
      state.eventValues.append(event.name)
    }
    let attributeCount = state.itemCount
    state.sortItems(0..<attributeCount)
    // The style declarations, sorted apart from the attributes.
    if hasStyles {
      index = 0
      while index < styles.count {
        _ = state.addItem(key: styles[index].key, kind: .text, source: index)
        index += 1
      }
      state.sortItems(attributeCount..<state.itemCount)
    }

    var position = 0
    while position < attributeCount {
      let item = state.items[position]
      sink.begin(name: state.keyBytes(item), count: item.keyLength, in: &state.bytes)
      switch item.kind {
      case .text:
        sink.value(attributes[item.source].value, in: &state.bytes)
      case .event:
        sink.value(state.eventValues[item.source], in: &state.bytes)
      case .classes:
        var first = true
        if item.source >= 0 { sink.value(attributes[item.source].value, in: &state.bytes); first = false }
        for name in classes {
          if !first { sink.separator(Self.space, in: &state.bytes) }
          sink.value(name, in: &state.bytes)
          first = false
        }
        if passthrough {
          if !first { sink.separator(Self.space, in: &state.bytes) }
          sink.literal("passthrough", in: &state.bytes)
        }
      case .style:
        var first = true
        if item.source >= 0 { sink.value(attributes[item.source].value, in: &state.bytes); first = false }
        var declaration = attributeCount
        while declaration < state.itemCount {
          let style = state.items[declaration]
          if !first { sink.separator(Self.space, in: &state.bytes) }
          sink.value(bytes: state.keyBytes(style), count: style.keyLength, in: &state.bytes)
          sink.literal(": ", in: &state.bytes)
          sink.value(styles[style.source].value, in: &state.bytes)
          sink.separator(Self.semicolon, in: &state.bytes)
          first = false
          declaration += 1
        }
      }
      sink.end(in: &state.bytes)
      position += 1
    }
  }

  private static let lessThan = UInt8(ascii: "<")
  private static let greaterThan = UInt8(ascii: ">")
  static let space = UInt8(ascii: " ")
  fileprivate static let quote = UInt8(ascii: "\"")
  static let semicolon = UInt8(ascii: ";")
}

/// Where `StaticHTMLFiberRenderer.assembleAttributes` sends what it assembled, one attribute at a time: `begin`, the
/// pieces of its value, `end`. `bytes` is the HTML output of the serialization in progress, which the markup sink
/// writes and any other sink leaves alone. Values arrive as the text they have, unescaped: escaping is the markup's.
protocol HTMLAttributeSink {
  mutating func begin(name: UnsafePointer<UInt8>, count: Int, in bytes: inout HTMLByteBuffer)
  /// A piece of the value made of a string.
  mutating func value(_ string: String, in bytes: inout HTMLByteBuffer)
  /// A piece of the value made of bytes (a style property's name).
  mutating func value(bytes pointer: UnsafePointer<UInt8>, count: Int, in bytes: inout HTMLByteBuffer)
  /// A piece of the value that needs no escaping: a space between classes or declarations, a semicolon.
  mutating func separator(_ byte: UInt8, in bytes: inout HTMLByteBuffer)
  /// A fixed piece of the value that needs no escaping.
  mutating func literal(_ text: StaticString, in bytes: inout HTMLByteBuffer)
  mutating func end(in bytes: inout HTMLByteBuffer)
}

/// ` name="value"`, the attribute as markup.
struct HTMLAttributeText: HTMLAttributeSink {
  @inline(__always)
  mutating func begin(name: UnsafePointer<UInt8>, count: Int, in bytes: inout HTMLByteBuffer) {
    bytes.append(StaticHTMLFiberRenderer.space)
    bytes.append(name, count: count)
    bytes.append("=\"")
  }
  @inline(__always)
  mutating func value(_ string: String, in bytes: inout HTMLByteBuffer) { bytes.appendEscaped(string) }
  @inline(__always)
  mutating func value(bytes pointer: UnsafePointer<UInt8>, count: Int, in bytes: inout HTMLByteBuffer) { bytes.appendEscaped(pointer, count: count) }
  @inline(__always)
  mutating func separator(_ byte: UInt8, in bytes: inout HTMLByteBuffer) { bytes.append(byte) }
  @inline(__always)
  mutating func literal(_ text: StaticString, in bytes: inout HTMLByteBuffer) { bytes.append(text) }
  @inline(__always)
  mutating func end(in bytes: inout HTMLByteBuffer) { bytes.append(StaticHTMLFiberRenderer.quote) }
}

extension _RenderNode {
  public var htmlDescription: String { StaticHTMLFiberRenderer().renderNode(self) }
}
