@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// The serializer as it was before the single-buffer writer replaced it (`HTMLRenderer.swift`): the reference the
/// writer must match byte for byte (`HTMLWriterReferenceTests`) and the baseline of `HTMLWriterBenchmarkTests`. Kept as it
/// was, only renamed; do not optimize it.
struct LegacyHTMLSerializer {
  let rootTag: String
  /// How many elements may nest before the output stops nesting them. An element opened below that depth is closed
  /// at once and its children follow it as its siblings, which is the tree an HTML parser builds anyway (both
  /// Chromium and WebKit stop nesting at 512 and attach what comes next to the last open element's parent). Written
  /// that way the parser does not see the depth: Chromium's cost per start tag grows with the depth of the stack of
  /// open elements, so a few thousand nested `div`s took seconds to parse. Nil keeps every level nested.
  let maxElementDepth: Int?
  // This vocabulary is immutable and shared by every serialization call.
  // Keeping it at renderer scope avoids allocating a Set for every element
  // during initial rendering and repeated lazy-row creation.
  private static let voidTags: Set<String> = [
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
    "meta", "param", "source", "track", "wbr"
  ]
  init(rootTag: String = "body", maxElementDepth: Int? = nil) {
    self.rootTag = rootTag
    self.maxElementDepth = maxElementDepth
  }
  /// Serializes an already-reconciled Fiber render node. Browser adapters use
  /// this backend-neutral entry point when committing a snapshot to the DOM.
  func renderNode(_ node: _RenderNode) -> String { String(decoding: renderNodeUTF8(node), as: UTF8.self) }

  /// Same output as `renderNode` as UTF-8 bytes. The browser host copies these
  /// straight into its transfer buffer, without building a `String` first.
  func renderNodeUTF8(_ node: _RenderNode) -> [UInt8] {
    var output: [UInt8] = []
    output.reserveCapacity(4096)
    write(node, into: &output)
    return output
  }

  /// A node whose children are being written: what its closing needs once they are.
  private struct WriteFrame {
    let node: _RenderNode
    /// Nil for a fragment, which writes no element of its own.
    let tag: String?
    let writesChildren: Bool
    let start: Int
    /// An element written past `maxElementDepth`: already closed, so it adds no depth and writes nothing at its end.
    var flat = false
    var next = 0
  }

  // One growing byte buffer for the whole tree: no per-node String, no
  // `map { }.joined()` copies at every depth, no per-value FFI for escaping.
  //
  // A loop over an explicit stack rather than a recursion: a view hierarchy hundreds of levels deep is a tree as
  // deep, and one WebAssembly frame per level of it is more than a WebKit Worker's stack holds.
  private func write(_ root: _RenderNode, into output: inout [UInt8]) {
    var stack: [WriteFrame] = []
    // Elements that are open and still nest: what the parser's stack of open elements holds.
    var depth = 0
    if let frame = open(root, into: &output, depth: depth) {
      if frame.tag != nil && !frame.flat { depth += 1 }
      stack.append(frame)
    }
    while !stack.isEmpty {
      let top = stack.count - 1
      let children = stack[top].writesChildren ? stack[top].node.children : []
      if stack[top].next < children.count {
        let child = children[stack[top].next]
        stack[top].next += 1
        if let frame = open(child, into: &output, depth: depth) {
          if frame.tag != nil && !frame.flat { depth += 1 }
          stack.append(frame)
        }
      } else {
        let frame = stack.removeLast()
        if frame.tag != nil && !frame.flat { depth -= 1 }
        close(frame, into: &output)
      }
    }
  }

  /// Writes what comes before a node's children, and returns the frame of an element that has children to write.
  private func open(_ node: _RenderNode, into output: inout [UInt8], depth: Int) -> WriteFrame? {
    switch node.kind {
    case .empty: return nil
    case .fragment:
      return WriteFrame(node: node, tag: nil, writesChildren: true, start: output.count)
    case .text:
      let plain = node.attributes.isEmpty && node.styles.isEmpty && node.classes.isEmpty && node.events.isEmpty
      if !plain {
        output.append(contentsOf: Self.spanOpen)
        writeAttributes(of: node, into: &output)
        output.append(Self.greaterThan)
      }
      appendEscaped(node.text ?? "", into: &output)
      if !plain { output.append(contentsOf: Self.spanClose) }
      return nil
    case .element(let tag):
      let start = output.count
      output.append(Self.lessThan)
      output.append(contentsOf: tag.utf8)
      writeAttributes(of: node, into: &output)
      output.append(Self.greaterThan)
      let writesChildren = !Self.voidTags.contains(tag.lowercased())
      let flat = writesChildren && maxElementDepth.map { depth >= $0 } == true
      var frame = WriteFrame(node: node, tag: tag, writesChildren: writesChildren, start: start)
      if flat {
        output.append(contentsOf: Self.closeOpen)
        output.append(contentsOf: tag.utf8)
        output.append(Self.greaterThan)
        frame.flat = true
      }
      return frame
    }
  }

  /// Writes what comes after a node's children.
  private func close(_ frame: WriteFrame, into output: inout [UInt8]) {
    guard let tag = frame.tag else { return }
    if frame.writesChildren && !frame.flat {
      output.append(contentsOf: Self.closeOpen)
      output.append(contentsOf: tag.utf8)
      output.append(Self.greaterThan)
    }
  }

  /// An attribute value written straight into the output: plain text, or the `class` / `style` value a
  /// node assembles from its own attribute plus its class list or style table.
  private enum AttributeValue {
    case text(String)
    case classes(prefix: String?)
    case style(prefix: String?)
  }

  /// Writes ` name="value"` for every attribute in name order. The attributes are collected in one small array
  /// (no copy of the attribute dictionary), and `class` and `style` are escaped piece by piece into the output
  /// instead of being joined into temporary strings first: escaping is bytewise, so the bytes are the same.
  private func writeAttributes(of node: _RenderNode, into output: inout [UInt8]) {
    // SwiftUI hit testing: pure layout containers let pointer events through.
    let passthrough = node._isHitTransparent
    let hasClasses = passthrough || !node.classes.isEmpty
    let hasStyles = !node.styles.isEmpty
    var entries: [(key: String, value: AttributeValue)] = []
    entries.reserveCapacity(node.attributes.count + node.events.count + 2)
    for (key, value) in node.attributes {
      if key == "class" && hasClasses { continue }
      if key == "style" && hasStyles { continue }
      entries.append((key: key, value: .text(value)))
    }
    if hasClasses { entries.append((key: "class", value: .classes(prefix: node.attributes["class"]))) }
    if hasStyles { entries.append((key: "style", value: .style(prefix: node.attributes["style"]))) }
    // Lifecycle, task, and geometry callbacks are coordinated by Fiber/host
    // adapters rather than DOM event listeners. Keep those implementation
    // details out of serialized HTML while preserving ordinary browser events.
    for (name, event) in node.events {
      guard name != "appear", name != "disappear", name != "task", name != "geometry", name != "geometryChange", name != "openURL", name != "presentation-dismiss", name != "web-navigation", name != "web-external-link" else { continue }
      let key = "data-fiber-event-\(name)"
      if let existing = entries.firstIndex(where: { $0.key == key }) {
        entries[existing].value = .text(event.name)
      } else {
        entries.append((key: key, value: .text(event.name)))
      }
    }
    // The same tiny insertion sort as `legacySortedStrings`, over the pairs.
    var index = 1
    while index < entries.count {
      let entry = entries[index]
      var position = index
      while position > 0 && entries[position - 1].key > entry.key {
        entries[position] = entries[position - 1]
        position -= 1
      }
      entries[position] = entry
      index += 1
    }
    for entry in entries {
      output.append(Self.space)
      output.append(contentsOf: entry.key.utf8)
      output.append(contentsOf: Self.equalsQuote)
      switch entry.value {
      case .text(let value):
        appendEscaped(value, into: &output)
      case .classes(let prefix):
        var first = true
        if let prefix { appendEscaped(prefix, into: &output); first = false }
        for name in node.classes {
          if !first { output.append(Self.space) }
          appendEscaped(name, into: &output)
          first = false
        }
        if passthrough {
          if !first { output.append(Self.space) }
          appendEscaped("passthrough", into: &output)
        }
      case .style(let prefix):
        var first = true
        if let prefix { appendEscaped(prefix, into: &output); first = false }
        for name in legacySortedStrings(Array(node.styles.keys)) {
          if !first { output.append(Self.space) }
          appendEscaped(name, into: &output)
          output.append(contentsOf: Self.colonSpace)
          appendEscaped(node.styles[name] ?? "", into: &output)
          output.append(Self.semicolon)
          first = false
        }
      }
      output.append(Self.quote)
    }
  }

  // Attribute and text escaping intentionally preserve the historical
  // five-entity behavior (`& < > " '`).
  // Raw HTML remains an explicit _RenderNode choice.
  private func appendEscaped(_ value: String, into output: inout [UInt8]) {
    var value = value
    value.withUTF8 { bytes in
      for byte in bytes {
        switch byte {
        case 0x26: output.append(contentsOf: Self.amp)
        case 0x3C: output.append(contentsOf: Self.lt)
        case 0x3E: output.append(contentsOf: Self.gt)
        case 0x22: output.append(contentsOf: Self.quot)
        case 0x27: output.append(contentsOf: Self.apos)
        default: output.append(byte)
        }
      }
    }
  }

  private static let lessThan = UInt8(ascii: "<")
  private static let greaterThan = UInt8(ascii: ">")
  private static let space = UInt8(ascii: " ")
  private static let quote = UInt8(ascii: "\"")
  private static let spanOpen: [UInt8] = Array("<span".utf8)
  private static let spanClose: [UInt8] = Array("</span>".utf8)
  private static let closeOpen: [UInt8] = Array("</".utf8)
  private static let equalsQuote: [UInt8] = Array("=\"".utf8)
  private static let colonSpace: [UInt8] = Array(": ".utf8)
  private static let semicolon = UInt8(ascii: ";")
  private static let amp: [UInt8] = Array("&amp;".utf8)
  private static let lt: [UInt8] = Array("&lt;".utf8)
  private static let gt: [UInt8] = Array("&gt;".utf8)
  private static let quot: [UInt8] = Array("&quot;".utf8)
  private static let apos: [UInt8] = Array("&#39;".utf8)
}

// Swift's generic Dictionary/Collection sort path is disproportionately
// expensive on Swift WASM and has triggered allocator faults in older browser
// runtimes. These tiny insertion sorts keep output deterministic while
// avoiding existential comparator closures and temporary sort buffers.
private func legacySortedStrings(_ values: [String]) -> [String] {
  var result = values
  guard result.count > 1 else { return result }
  var index = 1
  while index < result.count {
    let value = result[index]
    var position = index
    while position > 0 && result[position - 1] > value {
      result[position] = result[position - 1]
      position -= 1
    }
    result[position] = value
    index += 1
  }
  return result
}
