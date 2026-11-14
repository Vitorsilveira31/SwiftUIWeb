import SwiftUIWebCore

/// What the publisher keeps of one fiber's element between publications (Documentation/Architecture/BINARY_PATCHES.md,
/// "Swift side"). The host holds the element when `firstEpoch` is set and at or before the epoch the host acknowledged, and
/// the element still has the identity `idHash` stands for (its `data-embedded-node-id`, its tag, its namespace). `ownHash` is
/// the hash of its attributes and `childrenHash` the hash of its list of children in the DOM; each `...Since` is the epoch of
/// the first publication since which every publication that carried the element gave it that hash. A host that acknowledged
/// that epoch or a later one holds that state, whichever of the publications since then it applied.
package struct BinaryNodeRecord {
  package var firstEpoch: UInt64
  package var idHash: UInt64
  package var ownHash: UInt64
  package var ownSince: UInt64
  package var childrenHash: UInt64
  package var childrenSince: UInt64
  /// Whether the host keeps state in the element itself (a control, a tab view, a lazy list): it gets its attributes in every
  /// publication that visits it, and a publication visits it every time.
  package var ownsState: Bool

  package init(firstEpoch: UInt64 = 0, idHash: UInt64 = 0, ownHash: UInt64 = 0, ownSince: UInt64 = 0, childrenHash: UInt64 = 0, childrenSince: UInt64 = 0, ownsState: Bool = false) {
    self.firstEpoch = firstEpoch
    self.idHash = idHash
    self.ownHash = ownHash
    self.ownSince = ownSince
    self.childrenHash = childrenHash
    self.childrenSince = childrenSince
    self.ownsState = ownsState
  }
}

/// Writes a render tree as a binary publication (Documentation/Architecture/BINARY_PATCHES.md, "Format").
///
/// A host that holds nothing yet gets a `ROOT` record: the whole tree, built by `Tools/binary-publication.js` instead of
/// parsed. A host that holds the tree gets what changed since the epoch it acknowledged, as records that name an element by
/// its fiber's structural id: `ATTRS` (the whole attribute state of an element whose attributes changed, or that the host
/// keeps state in) and `CHILDREN` (the whole list of children of an element whose list changed: the elements the host
/// holds as `HELD`, the others built inline). Every record gives the whole state it names, so a host that dropped
/// publications in between still ends in the right place.
///
/// The tree is the DOM the HTML serializer's markup would build, element for element. The encoder takes the decisions the
/// HTML parser would take for that markup, so that both transports leave the same DOM: the nesting limit (an element opened
/// below `maxElementDepth` is closed at once and its children follow it as its siblings), void elements without children,
/// fragments flattened, empty nodes and empty texts left out, the namespace an element gets from its parents (`svg` and
/// `math` start one; `foreignObject`, `desc` and `title` in SVG hand their children back to HTML). What depends on the text
/// of a raw-text element, on a carriage return or on a script is decided by the page, which reads the strings.
///
/// Where the parser would restructure the tree (a `form` in a `form`, a `div` in a `table`, an element in an `option`; see
/// `BinaryParserFacts`), the encoder writes a tree the parser keeps instead (`Placement`): it adds the table parts the parser
/// would add, writes an element whose tag the parser would move as a neutral one with the role it stood for, and an
/// `option`'s content as its text. Every tree is encoded; `encode` returns nil only when a placeholder stands for an element
/// that cannot stay where it now sits, and the publisher then sends the whole tree.
package struct BinaryFiberEncoder {
  /// Elements nested before the rest follows as siblings (see `StaticHTMLFiberRenderer.maxElementDepth`).
  package var maxElementDepth: Int?
  /// The epoch the host acknowledged, and the epoch this publication covers.
  package var acked: UInt64
  package var covered: UInt64
  /// What the publisher keeps of the tree's root fiber, whose children are the top-level nodes of the page.
  package var rootRecord: BinaryNodeRecord
  /// What the publisher keeps of the fiber a visited node is the copy of.
  package var lookup: (_RenderNode) -> BinaryNodeRecord?
  /// The shapes the host holds, when the publication may use them.
  package var shapes: BinaryShapeTable?

  package init(maxElementDepth: Int? = nil, acked: UInt64, covered: UInt64, rootRecord: BinaryNodeRecord, shapes: BinaryShapeTable? = nil, lookup: @escaping (_RenderNode) -> BinaryNodeRecord?) {
    self.shapes = shapes
    self.maxElementDepth = maxElementDepth
    self.acked = acked
    self.covered = covered
    self.rootRecord = rootRecord
    self.lookup = lookup
  }

  /// A publication, and what the publisher keeps of each fiber once the host has it.
  package struct Output {
    package var bytes: [UInt8]
    /// The new record of every fiber whose element was visited; a zero record for a fiber that was visited but is not in the DOM.
    package var updates: [(node: _RenderNode, record: BinaryNodeRecord)]
    package var rootRecord: BinaryNodeRecord
    /// What the publication holds: whether it is a root, and how many of each record (HELD counts the elements named as held).
    package var isRoot: Bool
    package var attrsRecords: Int
    package var childrenRecords: Int
    package var heldNodes: Int
    /// Shapes defined by this publication, and subtrees it builds as shapes.
    package var shapeDefinitions: Int
    package var shapeInstances: Int
  }

  /// Subtrees counted per publication for the shapes: a publication that builds more has the rest built in full.
  private static let maximumShapePotentials = 4096

  private static let headerLength = 28
  /// Header flag 1: a reference publication follows the strings (see `encode`).
  private static let verifyFlag: UInt16 = 1
  /// Header flag 2: a record carries an element named for a view transition (`ViewTransitionNameModifier`). The page starts a
  /// view transition only for such a publication; every other publication is applied exactly as before.
  private static let transitionFlag: UInt16 = 2

  /// Whether the host holds the tree already, so that a publication lists changes.
  package var hostHoldsTree: Bool { rootRecord.firstEpoch != 0 && rootRecord.firstEpoch <= acked }

  /// `root` as a publication, or nil when an element the host holds would have to be written as another one where it now sits
  /// (see `Placement`): the publisher then encodes the whole tree, which holds no placeholder. `reference` is another
  /// publication of the same tree, encoded whole for a host that holds nothing (`encode` of a fresh encoder with no shapes). It
  /// is appended after the strings for the page's verification mode (`window.__binaryVerify`), which builds it and compares the
  /// DOM it ends with. Flag 1 says it is there; it is a complete publication with its own header, so the page reads it as any
  /// other.
  package func encode(_ root: _RenderNode, reference: UnsafeBufferPointer<UInt8>? = nil) -> Output? {
    shapes?.beginPublication()
    var engine = Engine(encoder: self)
    defer { engine.release() }
    engine.run(root)
    // The whole tree goes out instead: what the table says the host holds is not to be trusted.
    if engine.needsFull { shapes?.reset(); return nil }
    engine.useShapes()
    var out: [UInt8] = []
    let words = engine.words
    let strings = engine.strings.ownBytes
    out.reserveCapacity(Self.headerLength + words.count * 4 + strings.count + (reference?.count ?? 0))
    out.append(0)
    out.append(contentsOf: [UInt8(ascii: "S"), UInt8(ascii: "W"), UInt8(ascii: "B")])
    Self.append(UInt16(_BinaryFormat.version), to: &out)
    var flags = reference == nil ? UInt16(0) : Self.verifyFlag
    if engine.namedRecords { flags |= Self.transitionFlag }
    Self.append(flags, to: &out)
    Self.append(_BinaryFormat.atomsHash, to: &out)
    Self.append(shapes?.generation ?? 0, to: &out)
    Self.append(UInt32(words.count), to: &out)
    Self.append(UInt32(engine.strings.ownCount), to: &out)
    Self.append(UInt32(strings.count), to: &out)
    // The words are little-endian, which is how every host this runs on stores them.
    words.withUnsafeBytes { out.append(contentsOf: $0) }
    out.append(contentsOf: strings)
    if let reference { out.append(contentsOf: reference) }
    return Output(bytes: out, updates: engine.updates, rootRecord: engine.rootRecord, isRoot: !hostHoldsTree, attrsRecords: engine.attrsRecords, childrenRecords: engine.childrenRecords, heldNodes: engine.heldNodes, shapeDefinitions: engine.shapeDefinitions, shapeInstances: engine.shapeInstances)
  }

  private static func append(_ value: UInt16, to out: inout [UInt8]) {
    out.append(UInt8(truncatingIfNeeded: value))
    out.append(UInt8(truncatingIfNeeded: value >> 8))
  }

  private static func append(_ value: UInt32, to out: inout [UInt8]) {
    out.append(UInt8(truncatingIfNeeded: value))
    out.append(UInt8(truncatingIfNeeded: value >> 8))
    out.append(UInt8(truncatingIfNeeded: value >> 16))
    out.append(UInt8(truncatingIfNeeded: value >> 24))
  }

  // MARK: The walk

  /// Which kind of element the parser makes of a start tag: the namespace of its parent decides.
  private enum Context: UInt32 {
    case html = 0
    case svg = 1
    case mathml = 2
  }

  /// An open element as the parser's checks see it: its facts, its parent, and how many elements of the kinds the parser
  /// looks for are open from the root down to it.
  private struct Chain {
    var facts: UInt32
    var parent: Int32
    var forms: Int32
    var anchors: Int32
    var paragraphs: Int32
    var nobrs: Int32
  }

  /// What the cursor needs to know of a tag.
  private struct Oracle {
    let facts: [UInt32]
    let strings: BinaryStrings
    let limit: Int?

    func facts(of tag: String) -> UInt32 {
      var owned = tag
      return owned.withUTF8 { bytes -> UInt32 in
        guard let base = bytes.baseAddress else { return 0 }
        if let atom = strings.atomIndex(base, count: bytes.count) { return facts[Int(atom)] }
        // A tag written with capitals is the atom of its lowercase spelling to the parser.
        var lowered: [UInt8] = []
        var changed = false
        for byte in bytes {
          if byte >= 65 && byte <= 90 { lowered.append(byte + 32); changed = true } else { lowered.append(byte) }
        }
        guard changed else { return 0 }
        return lowered.withUnsafeBufferPointer { buffer in
          buffer.baseAddress.flatMap { strings.atomIndex($0, count: buffer.count) }.map { facts[Int($0)] } ?? 0
        }
      }
    }
  }

  /// How an element is written where it sits (see `Engine.placement`).
  private struct Placement {
    /// The facts of the tag written.
    var facts: UInt32
    /// The tag written instead of the node's own, and the attributes that say what it stands for.
    var tag: String? = nil
    var attributes: [(name: String, value: String)] = []
    /// Table parts written around it, outermost first, that no record names.
    var wrappers: [String] = []
    /// Written as its text.
    var flattens = false
    var isPlain: Bool { tag == nil && wrappers.isEmpty && !flattens }
  }

  /// A child of an element in the DOM.
  private enum Child {
    /// The placeholder for an element the host holds.
    case kept(_RenderNode)
    /// A text with no attributes of its own.
    case text(String)
    /// An element, or a text with attributes (a `span`). `flat`: opened below the nesting limit, so closed at once, with its
    /// children following it as its siblings.
    case element(_RenderNode, isSpan: Bool, flat: Bool, facts: UInt32)
    /// A node with no element of its own whose children are not in the DOM (a hidden branch).
    case hidden(_RenderNode)
  }

  /// The children an element has in the DOM, in order: fragments flattened, empty nodes and empty texts left out, the
  /// children of an element closed at once spliced in after it.
  private struct Cursor {
    var stack: [(nodes: [_RenderNode], index: Int)]
    var single: String?
    let depth: Int

    init(nodes: [_RenderNode], depth: Int) {
      stack = nodes.isEmpty ? [] : [(nodes, 0)]
      self.depth = depth
    }

    /// The cursor over the text of a `span`.
    init(text: String, depth: Int) {
      stack = []
      single = text.isEmpty ? nil : text
      self.depth = depth
    }

    mutating func next(_ oracle: Oracle) -> Child? {
      if let text = single { single = nil; return .text(text) }
      while true {
        guard let top = stack.indices.last else { return nil }
        if stack[top].index == stack[top].nodes.count { stack.removeLast(); continue }
        let node = stack[top].nodes[stack[top].index]
        stack[top].index += 1
        switch node.kind {
        case .empty:
          if node.children.isEmpty { continue }
          return .hidden(node)
        case .fragment:
          stack.append((node.children, 0))
        case .text:
          if node.attributes.isEmpty && node.styles.isEmpty && node.classes.isEmpty && node.events.isEmpty {
            let text = node.text ?? ""
            if text.isEmpty { continue }
            return .text(text)
          }
          return .element(node, isSpan: true, flat: false, facts: oracle.facts(of: "span"))
        case .element(let tag):
          let facts = oracle.facts(of: tag)
          if facts & BinaryParserFacts.isKeep != 0 { return .kept(node) }
          var flat = false
          if facts & BinaryParserFacts.isVoid == 0, let limit = oracle.limit, depth >= limit { flat = true }
          if flat && !node.children.isEmpty { stack.append((node.children, 0)) }
          return .element(node, isSpan: false, flat: flat, facts: facts)
        }
      }
    }
  }

  /// An element, as the walk meets it.
  private struct Item {
    let node: _RenderNode
    let isRoot: Bool
    let isSpan: Bool
    /// The structural id of its fiber.
    let handle: (index: UInt32, generation: UInt32)
    let idHash: UInt64
    /// The tag written for it and its facts: the node's own, or the one `Placement` writes instead.
    let tag: String
    let facts: UInt32
    /// Attributes `Placement` adds: the role of the element a neutral one stands for.
    let extra: [(name: String, value: String)]
    /// The record of its fiber when the host holds the element as it is.
    let record: BinaryNodeRecord
    /// What the publisher kept of the fiber before, whether the host holds it or not: an element sent again is the same
    /// element, and keeps the epochs it has been sent unchanged since.
    let prior: BinaryNodeRecord
    let held: Bool
    /// Its entry in the chains of open elements, which its children's parser checks start from.
    let chain: Int32
    /// The namespace the element is made in, and the one its children are made in.
    let elementContext: Context
    let childContext: Context
    /// Its children are the cursor from `childDepth`; not for a void element or an element closed at once.
    let childDepth: Int
    let hasChildren: Bool
  }

  /// The children of an element being written.
  private struct Frame {
    var cursor: Cursor
    let chain: Int32
    let context: Context
    var hash: UInt64
    /// The element, when the frame is the body of one that is being built.
    let item: Item?
    let ownHash: UInt64
    let ownsState: Bool
    /// The table parts `Placement` opened around the element, closed after it.
    var wrappers = 0
    /// For a shape (`BinaryShapeTable`): where the element's words start, the skeleton of what is below it so far, how many
    /// elements it holds, whether a shape may stand for it, whether the last child was a text, and the subtrees below it that
    /// a shape may stand for.
    var start = 0
    var skeleton: UInt64 = 0
    var elements = 1
    var shapeable = false
    var lastWasText = false
    var candidates: [BinaryShapePotential] = []
  }

  private struct Engine {
    var words: [UInt32] = []
    let strings: BinaryStrings
    let encoder: BinaryFiberEncoder
    var scratch = HTMLWriteState(capacity: 64)
    var sink: BinaryAttributeSink
    let oracle: Oracle
    var chains: [Chain] = []
    var tasks: [Item] = []
    var held: [Item] = []
    var updates: [(node: _RenderNode, record: BinaryNodeRecord)] = []
    var rootRecord: BinaryNodeRecord
    /// An element the host holds would be written as another one where it now sits: the publication is the whole tree.
    var needsFull = false
    var attrsRecords = 0, childrenRecords = 0, heldNodes = 0
    /// Whether a record written here names an element for a view transition (see `transitionFlag`).
    var namedRecords = false
    var reasserted: [Item] = []
    var shapeRoots: [BinaryShapePotential] = []
    var shapePotentials = 0
    var shapeDefinitions = 0, shapeInstances = 0

    init(encoder: BinaryFiberEncoder) {
      self.encoder = encoder
      let strings = BinaryStrings()
      self.strings = strings
      sink = BinaryAttributeSink(strings: strings)
      oracle = Oracle(facts: BinaryParserFacts.byAtom, strings: strings, limit: encoder.maxElementDepth)
      rootRecord = encoder.rootRecord
    }

    mutating func release() {
      scratch.release()
      sink.release()
    }

    // MARK: Records

    mutating func run(_ root: _RenderNode) {
      let covered = encoder.covered
      if !encoder.hostHoldsTree {
        // The host holds nothing: the whole tree, built.
        words.append(_BinaryFormat.opRoot)
        words.append(0)
        var count = 0
        let hash = writeList(Cursor(nodes: [root], depth: 0), chain: -1, context: .html, topLevel: &count)
        words[1] = UInt32(count)
        rootRecord = sentAgain(rootRecord, idHash: 0, ownHash: 0, childrenHash: hash, ownsState: false, covered: covered)
        return
      }
      tasks.append(Item(node: root, isRoot: true, isSpan: false, handle: (0, 0), idHash: 0, tag: "", facts: 0, extra: [], record: rootRecord, prior: rootRecord, held: true, chain: -1,
                        elementContext: .html, childContext: .html, childDepth: 0, hasChildren: true))
      while !needsFull, let item = tasks.popLast() { process(item) }
      if !words.isEmpty { for item in reasserted { writeAttrsRecord(item) } }
    }

    mutating func writeAttrsRecord(_ item: Item) {
      attrsRecords += 1
      words.append(_BinaryFormat.opAttrs)
      words.append(item.handle.index &+ 1)
      words.append(item.handle.generation)
      _ = writeAttributes(item.node, isElement: !item.isSpan, facts: item.facts, extra: item.extra, dropsNodeID: true)
    }

    /// An element the host holds that was visited: its attributes when they changed or the host keeps state in them, its
    /// list of children when it changed, and then whatever below it was visited too.
    mutating func process(_ item: Item) {
      let acked = encoder.acked, covered = encoder.covered
      var record = item.record
      if !item.isRoot {
        let own = assemble(item.node, isElement: !item.isSpan, facts: item.facts, extra: item.extra, collects: false)
        let hostOwned = own.hostOwned
        let ownHeld = own.hash == record.ownHash && record.ownSince != 0 && record.ownSince <= acked
        if !ownHeld {
          writeAttrsRecord(item)
        } else if hostOwned {
          // The host's state in it is written again when the publication has something else to say (the markup of a publication
          // that says nothing new is not applied either).
          reasserted.append(item)
        }
        record.ownsState = hostOwned
        if own.hash != record.ownHash || record.ownSince == 0 { record.ownSince = covered }
        record.ownHash = own.hash
      }
      // The list of children, as the host would hold it.
      var hash = BinaryHash.seed
      var anyNew = false
      held.removeAll(keepingCapacity: true)
      var cursor = cursor(of: item)
      while let child = cursor.next(oracle) {
        switch child {
        case .kept(let node):
          guard let handle = keep(node, context: item.childContext, parent: item.chain) else { return }
          hash = BinaryHash.mix(hash, Self.word(handle))
        case .text(let text):
          hash = BinaryHash.mix(BinaryHash.mix(hash, 0x7465_7874), text)
        case .element(let node, let isSpan, let flat, let facts):
          let place = placement(facts, isSpan: isSpan, node: node, in: item.childContext, parent: item.chain)
          if place.flattens {
            hash = BinaryHash.mix(BinaryHash.mix(hash, 0x7465_7874), Self.text(of: node))
            continue
          }
          let child = classify(node, isSpan: isSpan, flat: flat, place: place, context: item.childContext, parentChain: wrapperChain(place, parent: item.chain), parentDepth: cursor.depth)
          hash = BinaryHash.mix(hash, Self.word(child.handle))
          if child.held { held.append(child) } else { anyNew = true }
        case .hidden:
          break
        }
      }
      let childrenChanged = hash != record.childrenHash || record.childrenSince == 0
      // The children of an icon are what the page replaces with its glyph: it is not told them again for being new to the host.
      let iconContent = !item.isRoot && !item.isSpan && item.node.attributes["data-symbol"] != nil
      if childrenChanged || record.childrenSince > acked || (anyNew && !iconContent) {
        childrenRecords += 1
        words.append(_BinaryFormat.opChildren)
        words.append(item.isRoot ? 0 : item.handle.index &+ 1)
        words.append(item.isRoot ? 0 : item.handle.generation)
        var top = 0
        _ = writeList(self.cursor(of: item), chain: item.chain, context: item.childContext, topLevel: &top)
        words.append(_BinaryFormat.opEnd)
        if needsFull { return }
      } else {
        tasks.append(contentsOf: held)
      }
      if childrenChanged { record.childrenSince = covered }
      record.childrenHash = hash
      if item.isRoot { rootRecord = record } else { updates.append((item.node, record)) }
    }

    func cursor(of item: Item) -> Cursor {
      if item.isRoot { return Cursor(nodes: [item.node], depth: 0) }
      if !item.hasChildren { return Cursor(nodes: [], depth: item.childDepth) }
      if item.isSpan { return Cursor(text: item.node.text ?? "", depth: item.childDepth) }
      return Cursor(nodes: item.node.children, depth: item.childDepth)
    }

    /// The facts and the identity of a visited element, written where it sits as `place` says, and whether the host holds it
    /// as it is. `parentChain` is the innermost table part `place` opens around it, if any.
    mutating func classify(_ node: _RenderNode, isSpan: Bool, flat: Bool, place: Placement, context: Context, parentChain: Int32, parentDepth: Int) -> Item {
      // An element without an id of its own (a tree that was not made by fibers) cannot be named by a record: the host builds
      // it again every time.
      let handle = Self.handle(of: node) ?? Self.noHandle
      let tag = place.tag ?? (isSpan ? "span" : Self.tag(of: node))
      let facts = place.facts
      let elementContext = Self.elementContext(facts: facts, in: context)
      let idHash = Self.identity(of: node, tag: tag, context: elementContext)
      let record = encoder.lookup(node) ?? BinaryNodeRecord()
      let held = handle != Self.noHandle && encoder.hostHoldsTree && record.firstEpoch != 0 && record.firstEpoch <= encoder.acked && record.idHash == idHash
      // A neutral element that stands for another has no children of its own when it stands for a void one.
      let opensChildren = !flat && facts & BinaryParserFacts.isVoid == 0
      return Item(node: node, isRoot: false, isSpan: isSpan, handle: handle, idHash: idHash, tag: tag, facts: facts, extra: place.attributes,
                  record: held ? record : BinaryNodeRecord(), prior: record, held: held,
                  chain: makeChain(facts, parent: parentChain), elementContext: elementContext,
                  childContext: Self.childContext(tag: tag, element: elementContext, node: node), childDepth: parentDepth + 1,
                  hasChildren: opensChildren)
    }

    /// The record of an element that was built in this publication. The publication carries all of its state, but an element
    /// that was carried before, under the same identity and with the same state, has been carried unchanged since then:
    /// a host that acknowledged any publication since holds it. (Without this a host that always acknowledges a little late
    /// would be sent the whole tree again by every publication.)
    func sentAgain(_ prior: BinaryNodeRecord, idHash: UInt64, ownHash: UInt64, childrenHash: UInt64, ownsState: Bool, covered: UInt64) -> BinaryNodeRecord {
      let continues = prior.firstEpoch != 0 && prior.idHash == idHash
      return BinaryNodeRecord(firstEpoch: continues ? prior.firstEpoch : covered, idHash: idHash, ownHash: ownHash,
                              ownSince: continues && prior.ownSince != 0 && prior.ownHash == ownHash ? prior.ownSince : covered,
                              childrenHash: childrenHash,
                              childrenSince: continues && prior.childrenSince != 0 && prior.childrenHash == childrenHash ? prior.childrenSince : covered,
                              ownsState: ownsState)
    }

    /// The handle of the element a placeholder stands for, or nil (and the whole tree goes out) when the element is not the one
    /// the host holds: the placeholder was made for an element of another identity (its namespace changed under it), or the
    /// element would be written as another one where it now sits than where it was built (see `Placement`). Table parts
    /// `Placement` adds around it do not change the element.
    mutating func keep(_ node: _RenderNode, context: Context, parent: Int32) -> (index: UInt32, generation: UInt32)? {
      let place = placement(oracle.facts(of: Self.keptTag(of: node)), isSpan: false, node: nil, in: context, parent: parent)
      let tag = place.tag ?? Self.keptTag(of: node)
      let elementContext = Self.elementContext(facts: place.facts, in: context)
      guard encoder.hostHoldsTree, !place.flattens, let handle = Self.handle(of: node), let record = encoder.lookup(node),
            record.firstEpoch != 0, record.firstEpoch <= encoder.acked else { needsFull = true; return nil }
      // A `p` was built as a neutral block when it held one (`closesParagraph(below:)`), which its placeholder does not say.
      let identity = Self.identity(of: node, tag: tag, context: elementContext)
      guard record.idHash == identity || place.facts & BinaryParserFacts.paragraph != 0 && record.idHash == Self.identity(of: node, tag: "div", context: elementContext) else {
        needsFull = true
        return nil
      }
      return handle
    }

    /// Opens the table parts `place` adds, as elements of their own that no record names; returns the chain of the innermost.
    mutating func openWrappers(_ place: Placement, parent: Int32) -> Int32 {
      var chain = parent
      for tag in place.wrappers {
        words.append(_BinaryFormat.opElement)
        words.append(Self.noHandle.index &+ 1)
        words.append(Self.noHandle.generation)
        words.append(0)
        words.append(stringIndex(of: tag, dropsNUL: false))
        words.append(0)
        chain = makeChain(oracle.facts(of: tag), parent: chain)
      }
      return chain
    }

    /// The chain the element below the table parts `place` adds sits in, without writing them (for the records' hashes).
    mutating func wrapperChain(_ place: Placement, parent: Int32) -> Int32 {
      var chain = parent
      for tag in place.wrappers { chain = makeChain(oracle.facts(of: tag), parent: chain) }
      return chain
    }

    mutating func closeWrappers(_ count: Int) {
      for _ in 0..<count { words.append(_BinaryFormat.opEnd) }
    }

    /// Writes the list of nodes a cursor yields, and everything built inside them, as nodes. Returns the hash of the list.
    mutating func writeList(_ start: Cursor, chain: Int32, context: Context, topLevel: inout Int) -> UInt64 {
      let covered = encoder.covered
      let shaping = encoder.shapes != nil
      var frames: [Frame] = [Frame(cursor: start, chain: chain, context: context, hash: BinaryHash.seed, item: nil, ownHash: 0, ownsState: false)]
      var result = BinaryHash.seed
      while !needsFull, let top = frames.indices.last {
        guard let child = frames[top].cursor.next(oracle) else {
          let frame = frames.removeLast()
          if let item = frame.item {
            words.append(_BinaryFormat.opEnd)
            closeWrappers(frame.wrappers)
            updates.append((item.node, sentAgain(item.prior, idHash: item.idHash, ownHash: frame.ownHash, childrenHash: frame.hash, ownsState: frame.ownsState, covered: covered)))
            if shaping { closeShape(frame, into: &frames[frames.count - 1]) }
          } else {
            result = frame.hash
            shapeRoots.append(contentsOf: frame.candidates)
          }
          continue
        }
        let parentChain = frames[top].chain
        let parentContext = frames[top].context
        switch child {
        case .text(let text):
          let place = textPlacement(text, parent: parentChain)
          if top == 0 { topLevel += 1 }
          if !place.wrappers.isEmpty { frames[top].shapeable = false }
          _ = openWrappers(place, parent: parentChain)
          words.append(_BinaryFormat.opText)
          words.append(stringIndex(of: text, dropsNUL: true))
          closeWrappers(place.wrappers.count)
          frames[top].hash = BinaryHash.mix(BinaryHash.mix(frames[top].hash, 0x7465_7874), text)
          // Two texts in a row are one text node, which a shape does not stand for.
          if frames[top].lastWasText { frames[top].shapeable = false }
          frames[top].lastWasText = true
          frames[top].skeleton = BinaryHash.mix(frames[top].skeleton, 0x7465_7874)
        case .kept(let node):
          guard let handle = keep(node, context: parentContext, parent: parentChain) else { break }
          if top == 0 { topLevel += 1 }
          heldNodes += 1
          let place = placement(oracle.facts(of: Self.keptTag(of: node)), isSpan: false, node: nil, in: parentContext, parent: parentChain)
          _ = openWrappers(place, parent: parentChain)
          words.append(_BinaryFormat.opHeld)
          words.append(handle.index &+ 1)
          words.append(handle.generation)
          closeWrappers(place.wrappers.count)
          frames[top].hash = BinaryHash.mix(frames[top].hash, Self.word(handle))
          frames[top].shapeable = false
        case .hidden:
          break
        case .element(let node, let isSpan, let flat, let facts):
          let place = placement(facts, isSpan: isSpan, node: node, in: parentContext, parent: parentChain)
          if place.flattens {
            // What the parser keeps of an element in an `option`: its text.
            let text = Self.text(of: node)
            frames[top].shapeable = false
            if text.isEmpty { break }
            if top == 0 { topLevel += 1 }
            words.append(_BinaryFormat.opText)
            words.append(stringIndex(of: text, dropsNUL: true))
            frames[top].hash = BinaryHash.mix(BinaryHash.mix(frames[top].hash, 0x7465_7874), text)
            frames[top].lastWasText = true
            break
          }
          if !place.isPlain { frames[top].shapeable = false }
          let wrapped = openWrappers(place, parent: parentChain)
          let item = classify(node, isSpan: isSpan, flat: flat, place: place, context: parentContext, parentChain: wrapped, parentDepth: frames[top].cursor.depth)
          if top == 0 { topLevel += 1 }
          frames[top].hash = BinaryHash.mix(frames[top].hash, Self.word(item.handle))
          if item.held {
            heldNodes += 1
            words.append(_BinaryFormat.opHeld)
            words.append(item.handle.index &+ 1)
            words.append(item.handle.generation)
            closeWrappers(place.wrappers.count)
            tasks.append(item)
            frames[top].shapeable = false
            break
          }
          // Built here: its header, then its children.
          frames[top].lastWasText = false
          let start = words.count
          let hasHandle = item.handle != Self.noHandle
          words.append(item.elementContext == .html ? _BinaryFormat.opElement : _BinaryFormat.opElementNs)
          words.append(item.handle.index &+ 1)
          words.append(item.handle.generation)
          words.append(hasHandle ? descriptorIndex(of: item.node) : 0)
          if item.elementContext != .html { words.append(item.elementContext.rawValue) }
          let tag = stringIndex(of: item.tag, dropsNUL: false)
          words.append(tag)
          let own = writeAttributes(item.node, isElement: !item.isSpan, facts: item.facts, extra: item.extra, dropsNodeID: hasHandle)
          let itemCursor = cursor(of: item)
          var frame = Frame(cursor: itemCursor, chain: item.chain, context: item.childContext, hash: BinaryHash.seed, item: item, ownHash: own.hash, ownsState: own.hostOwned)
          frame.wrappers = place.wrappers.count
          if shaping {
            frame.start = start
            frame.shapeable = hasHandle && !own.hostOwned && !own.forbidsShape && item.facts & (BinaryParserFacts.hostOwned | BinaryParserFacts.specialText | BinaryParserFacts.neverBuilt) == 0
            frame.skeleton = skeletonSeed(item: item, tag: tag, hasHandle: hasHandle)
          }
          frames.append(frame)
        }
      }
      return result
    }

    /// What names an element's own part of a shape: its tag, its namespace, its attribute names in order and whether it has an id.
    func skeletonSeed(item: Item, tag: UInt32, hasHandle: Bool) -> UInt64 {
      var seed = BinaryHash.mix(BinaryHash.seed, UInt64(item.elementContext.rawValue))
      seed = BinaryHash.mix(seed, strings.identity(of: tag))
      let count = sink.pairs.count / 2
      seed = BinaryHash.mix(seed, UInt64(count) << 1 | (hasHandle ? 1 : 0))
      var index = 0
      while index < count {
        seed = BinaryHash.mix(seed, strings.identity(of: sink.pairs[index * 2]))
        index += 1
      }
      return seed
    }

    /// An element's frame is done: tells the frame of its parent what is below it, and which subtrees a shape may stand for. Which
    /// of them are chosen is for the end of the publication, when it is known how often each skeleton was met.
    mutating func closeShape(_ frame: Frame, into parent: inout Frame) {
      guard let table = encoder.shapes else { return }
      parent.skeleton = BinaryHash.mix(parent.skeleton, frame.skeleton)
      parent.elements += frame.elements
      parent.shapeable = parent.shapeable && frame.shapeable
      guard frame.shapeable else {
        // Something in it is not for a shape, so nothing above it is: what is below it that is one stays one.
        shapeRoots.append(contentsOf: frame.candidates)
        return
      }
      // A subtree too small for a shape holds none; and a publication that builds this many subtrees is not counting them all.
      guard frame.elements >= table.minimumElements else { return }
      guard shapePotentials < BinaryFiberEncoder.maximumShapePotentials else {
        parent.candidates.append(contentsOf: frame.candidates)
        return
      }
      shapePotentials += 1
      let key = BinaryHash.mix(frame.skeleton, UInt64(frame.elements))
      table.touch(key)
      parent.candidates.append(BinaryShapePotential(key: key, start: frame.start, end: words.count, children: frame.candidates))
    }

    /// Builds the subtrees that are shapes as `SHAPE` nodes, and carries the definitions the host may lack.
    mutating func useShapes() {
      guard let table = encoder.shapes, !shapeRoots.isEmpty || table.newestDefinition > encoder.acked else { return }
      var assembler = BinaryShapeAssembler(strings: strings, table: table, covered: encoder.covered, acked: encoder.acked)
      words = assembler.assemble(words, shapeRoots, defineAt: words.first == _BinaryFormat.opRoot ? 2 : 0)
      shapeDefinitions = assembler.definitions
      shapeInstances = assembler.instances
    }

    /// The string of an element's id after its index and generation: what tells it from the others the same fiber made.
    func descriptorIndex(of node: _RenderNode) -> UInt32 {
      guard var id = node.attributes["data-embedded-node-id"] else { return strings.internEmpty() }
      return id.withUTF8 { bytes in
        var colons = 0
        var offset = 0
        while offset < bytes.count {
          if bytes[offset] == UInt8(ascii: ":") { colons += 1; if colons == 2 { offset += 1; break } }
          offset += 1
        }
        guard colons == 2, offset < bytes.count, let base = bytes.baseAddress else { return strings.internEmpty() }
        return strings.intern(base + offset, count: bytes.count - offset)
      }
    }

    // MARK: Attributes

    /// Assembles the attributes of `node` and hashes them; collects them as (name, value) pairs when asked.
    mutating func assemble(_ node: _RenderNode, isElement: Bool, facts: UInt32, extra: [(name: String, value: String)] = [], collects: Bool) -> (hash: UInt64, hostOwned: Bool) {
      sink.start(collects: collects)
      var info = StaticHTMLFiberRenderer.AttributeInfo()
      StaticHTMLFiberRenderer.assembleAttributes(of: node, isElement: isElement, into: &scratch, info: &info, sink: &sink)
      for attribute in extra where node.attributes[attribute.name] == nil { sink.extra(attribute.name, attribute.value) }
      // The tags the host keeps state in, the attributes that say so (`AttributeInfo`) and the tab view, which applies the
      // selection before Swift answers.
      let hostOwned = info.hostOwned || facts & BinaryParserFacts.hostOwned != 0 || Self.hasClass(node, "tab-view")
      return (sink.hash, hostOwned)
    }

    /// Writes the attributes of `node` as a count and (name, value) pairs. Returns their hash.
    mutating func writeAttributes(_ node: _RenderNode, isElement: Bool, facts: UInt32, extra: [(name: String, value: String)] = [], dropsNodeID: Bool) -> (hash: UInt64, hostOwned: Bool, forbidsShape: Bool) {
      if node.styles["view-transition-name"] != nil { namedRecords = true }
      sink.dropsNodeID = dropsNodeID
      let result = assemble(node, isElement: isElement, facts: facts, extra: extra, collects: true)
      sink.dropsNodeID = false
      words.append(UInt32(sink.pairs.count / 2))
      words.append(contentsOf: sink.pairs)
      return (result.hash, result.hostOwned, sink.forbidsShape)
    }

    func stringIndex(of string: String, dropsNUL: Bool) -> UInt32 {
      var owned = string
      return owned.withUTF8 { bytes in
        guard let base = bytes.baseAddress else { return strings.internEmpty() }
        // Text and attribute values cannot hold a NUL (it separates the strings): the parser drops it from the text of
        // an element and turns it into U+FFFD in an attribute.
        if bytes.contains(0) {
          var scrubbed: [UInt8] = []
          for byte in bytes {
            if byte != 0 { scrubbed.append(byte) } else if !dropsNUL { scrubbed.append(contentsOf: [0xEF, 0xBF, 0xBD]) }
          }
          return scrubbed.withUnsafeBufferPointer { buffer in buffer.baseAddress.map { strings.intern($0, count: buffer.count) } ?? strings.internEmpty() }
        }
        return strings.intern(base, count: bytes.count)
      }
    }

    // MARK: What the parser keeps

    mutating func makeChain(_ facts: UInt32, parent: Int32) -> Int32 {
      var chain = Chain(facts: facts, parent: parent, forms: 0, anchors: 0, paragraphs: 0, nobrs: 0)
      if parent >= 0 {
        let above = chains[Int(parent)]
        chain.forms = above.forms
        chain.anchors = above.anchors
        chain.paragraphs = above.paragraphs
        chain.nobrs = above.nobrs
      }
      if facts & BinaryParserFacts.form != 0 { chain.forms += 1 }
      if facts & BinaryParserFacts.anchor != 0 { chain.anchors += 1 }
      if facts & BinaryParserFacts.paragraph != 0 { chain.paragraphs += 1 }
      if facts & BinaryParserFacts.nobr != 0 { chain.nobrs += 1 }
      chains.append(chain)
      return Int32(chains.count - 1)
    }

    /// How an element with these facts is written as a child of the innermost open element, in `context`, so that the parser
    /// keeps it there: as it is; inside the table parts the parser would add; as a neutral element, with the role of the one it
    /// stands for, where the parser would close or move it; or, in an `option`, as its text.
    func placement(_ f: UInt32, isSpan: Bool, node: _RenderNode?, in context: Context, parent: Int32) -> Placement {
      // In SVG and MathML content only the HTML elements the parser moves out of it matter: a text with attributes stays one
      // (`tspan`, `mtext`), and anything else a group (`g`, `mrow`).
      if context != .html {
        guard f & BinaryParserFacts.breaksOutOfForeign != 0 else { return Placement(facts: f) }
        if context == .svg { return rewritten(isSpan ? "tspan" : "g") }
        return rewritten(isSpan ? "mtext" : "mrow")
      }
      let above = parent >= 0 ? chains[Int(parent)] : Chain(facts: 0, parent: -1, forms: 0, anchors: 0, paragraphs: 0, nobrs: 0)
      let parentFacts = above.facts
      if parentFacts & BinaryParserFacts.option != 0 { return Placement(facts: f, flattens: true) }
      var place = Placement(facts: f)
      if f & BinaryParserFacts.neverBuilt != 0 {
        place = rewritten("div")
      } else if f & BinaryParserFacts.form != 0 && above.forms > 0 {
        place = rewritten("div", role: "form")
      } else if f & BinaryParserFacts.anchor != 0 && above.anchors > 0 {
        place = rewritten("span", role: "link")
      } else if f & BinaryParserFacts.nobr != 0 && above.nobrs > 0 {
        place = rewritten("span")
      } else if f & BinaryParserFacts.paragraph != 0, let node, closesParagraph(below: node) {
        // A block in a `p` closes it: a paragraph that holds one is a neutral block, so that nothing in it is moved.
        place = rewritten("div", role: "paragraph")
      } else if f & BinaryParserFacts.listItem != 0 && opensListItem(BinaryParserFacts.listItem, from: parent) {
        place = rewritten("div", role: "listitem")
      } else if f & BinaryParserFacts.definition != 0 && opensListItem(BinaryParserFacts.definition, from: parent) {
        place = rewritten("div")
      } else if f & BinaryParserFacts.heading != 0 && parentFacts & BinaryParserFacts.heading != 0 {
        place = rewritten("div", role: "heading", level: node.map(Self.tag(of:)).flatMap(Self.headingLevel))
      } else if f & BinaryParserFacts.table != 0 && parentFacts & BinaryParserFacts.caption != 0 {
        place = rewritten("div", role: "table")
      } else if parentFacts & BinaryParserFacts.select != 0 && f & (BinaryParserFacts.option | BinaryParserFacts.optionGroup | BinaryParserFacts.allowedInSelect) == 0 {
        place = rewritten("option")
      } else if parentFacts & BinaryParserFacts.optionGroup != 0 && f & (BinaryParserFacts.option | BinaryParserFacts.allowedInSelect) == 0 {
        place = rewritten("option")
      }
      place.wrappers = Self.tableParts(for: place.facts, under: parentFacts)
      return place
    }

    /// Whether something below a `p` would close it: a block, or an element the host holds, whose content is not visited.
    func closesParagraph(below node: _RenderNode) -> Bool {
      var stack = node.children
      while let next = stack.popLast() {
        switch next.kind {
        case .element(let tag):
          let facts = oracle.facts(of: tag)
          if facts & (BinaryParserFacts.closesParagraph | BinaryParserFacts.isKeep) != 0 { return true }
          stack.append(contentsOf: next.children)
        case .fragment, .empty:
          stack.append(contentsOf: next.children)
        case .text:
          break
        }
      }
      return false
    }

    /// A text is moved out of a table by the parser unless it is white space: it goes in a cell of its own.
    func textPlacement(_ text: String, parent: Int32) -> Placement {
      guard parent >= 0 else { return Placement(facts: 0) }
      let parentFacts = chains[Int(parent)].facts
      guard parentFacts & BinaryParserFacts.tableContent != 0 else { return Placement(facts: 0) }
      for byte in text.utf8 where !(byte == 32 || byte == 9 || byte == 10 || byte == 12 || byte == 13) {
        var place = Placement(facts: 0)
        place.wrappers = Self.tableParts(for: 0, under: parentFacts)
        return place
      }
      return Placement(facts: 0)
    }

    func rewritten(_ tag: String, role: String? = nil, level: String? = nil) -> Placement {
      var place = Placement(facts: oracle.facts(of: tag))
      place.tag = tag
      if let role { place.attributes.append((name: "role", value: role)) }
      if let level { place.attributes.append((name: "aria-level", value: level)) }
      return place
    }

    /// The table parts the parser adds between a parent with `parentFacts` and a child with `facts`, outermost first: a row
    /// in a table gets a section, a cell a section and a row, anything else in a table a section, a row and a cell, and a part
    /// outside a table the table and the parts above it. The content of a column group is columns only, and stays as written.
    static func tableParts(for facts: UInt32, under parentFacts: UInt32) -> [String] {
      typealias P = BinaryParserFacts
      if parentFacts & P.table != 0 {
        if facts & (P.caption | P.columnGroup | P.tableSection | P.allowedInTable) != 0 { return [] }
        if facts & P.tableRow != 0 { return ["tbody"] }
        if facts & P.tableCell != 0 { return ["tbody", "tr"] }
        if facts & P.column != 0 { return ["colgroup"] }
        return ["tbody", "tr", "td"]
      }
      if parentFacts & P.tableSection != 0 {
        if facts & (P.tableRow | P.allowedInTable) != 0 { return [] }
        if facts & P.tableCell != 0 { return ["tr"] }
        return ["tr", "td"]
      }
      if parentFacts & P.tableRow != 0 {
        return facts & (P.tableCell | P.allowedInTable) != 0 ? [] : ["td"]
      }
      if parentFacts & P.columnGroup != 0 { return [] }
      if facts & P.tableCell != 0 { return ["table", "tbody", "tr"] }
      if facts & P.tableRow != 0 { return ["table", "tbody"] }
      if facts & (P.tableSection | P.caption | P.columnGroup) != 0 { return ["table"] }
      if facts & P.column != 0 { return ["table", "colgroup"] }
      return []
    }

    static func headingLevel(_ tag: String) -> String? {
      guard tag.utf8.count == 2, let digit = tag.utf8.last, digit >= 49 && digit <= 54 else { return nil }
      return String(Character(Unicode.Scalar(digit)))
    }

    /// The text of a subtree, in order: what the parser keeps of it inside an `option`.
    static func text(of node: _RenderNode) -> String {
      var result = ""
      var stack = [node]
      while let next = stack.popLast() {
        if next.kind == .text { result += next.text ?? "" }
        for child in next.children.reversed() { stack.append(child) }
      }
      return result
    }

    /// Whether an `li` (or a `dd` or `dt`) the parser would close is open: the search goes up to the first special element
    /// that is not an `address`, a `div` or a `p`.
    func opensListItem(_ kind: UInt32, from chain: Int32) -> Bool {
      var index = chain
      while index >= 0 {
        let facts = chains[Int(index)].facts
        if facts & kind != 0 { return true }
        if facts & BinaryParserFacts.blocksListScan != 0 { return false }
        index = chains[Int(index)].parent
      }
      return false
    }

    // MARK: Identity

    static let noHandle: (index: UInt32, generation: UInt32) = (UInt32.max, 0)

    static func word(_ handle: (index: UInt32, generation: UInt32)) -> UInt64 { UInt64(handle.index) << 32 | UInt64(handle.generation) }

    /// The structural id a node's `data-embedded-node-id` starts with: `index:generation:descriptor`.
    static func handle(of node: _RenderNode) -> (index: UInt32, generation: UInt32)? {
      guard let id = node.attributes["data-embedded-node-id"] else { return nil }
      var index: UInt32 = 0, generation: UInt32 = 0
      var field = 0
      var digits = 0
      for byte in id.utf8 {
        if byte == UInt8(ascii: ":") {
          field += 1
          if field == 2 { break }
          digits = 0
          continue
        }
        guard byte >= 48 && byte <= 57 else { return nil }
        digits += 1
        if field == 0 { index = index &* 10 &+ UInt32(byte - 48) } else { generation = generation &* 10 &+ UInt32(byte - 48) }
      }
      return field >= 1 && digits > 0 ? (index, generation) : nil
    }

    /// What makes an element a different one to the host: its whole id (the descriptor included), its tag, its namespace.
    static func identity(of node: _RenderNode, tag: String, context: Context) -> UInt64 {
      var hash = BinaryHash.mix(BinaryHash.seed, node.attributes["data-embedded-node-id"] ?? "")
      hash = BinaryHash.mix(hash, tag)
      return BinaryHash.mix(hash, UInt64(context.rawValue))
    }

    static func tag(of node: _RenderNode) -> String {
      if case .element(let tag) = node.kind { return tag }
      return "span"
    }

    static func keptTag(of node: _RenderNode) -> String { node.attributes["data-keep-tag"] ?? "" }

    static func hasClass(_ node: _RenderNode, _ name: String) -> Bool {
      for candidate in node.classes where candidate == name { return true }
      return false
    }

    // MARK: Namespaces

    /// The namespace of an element made by a start tag with these facts among the children of an element made in `context`.
    static func elementContext(facts: UInt32, in context: Context) -> Context {
      switch context {
      case .html:
        if facts & BinaryParserFacts.startsSvg != 0 { return .svg }
        if facts & BinaryParserFacts.startsMathML != 0 { return .mathml }
        return .html
      case .svg: return .svg
      case .mathml: return .mathml
      }
    }

    /// The namespace of the children of an element: SVG's `foreignObject`, `desc` and `title` and MathML's text
    /// elements, and an `annotation-xml` of HTML, are where the parser goes back to HTML.
    static func childContext(tag: String, element: Context, node: _RenderNode) -> Context {
      switch element {
      case .html: return .html
      case .svg:
        return isName(tag, "foreignobject") || isName(tag, "desc") || isName(tag, "title") ? .html : .svg
      case .mathml:
        if isName(tag, "mi") || isName(tag, "mo") || isName(tag, "mn") || isName(tag, "ms") || isName(tag, "mtext") { return .html }
        // `annotation-xml` holds HTML when it says so.
        if isName(tag, "annotation-xml"), let encoding = node.attributes["encoding"], isName(encoding, "text/html") || isName(encoding, "application/xhtml+xml") { return .html }
        return .mathml
      }
    }

    /// Whether `name` is `lowercase` once its ASCII letters are lowercased (the parser reads names that way).
    static func isName(_ name: String, _ lowercase: StaticString) -> Bool {
      var index = 0
      for byte in name.utf8 {
        if index == lowercase.utf8CodeUnitCount { return false }
        if (byte >= 65 && byte <= 90 ? byte + 32 : byte) != lowercase.utf8Start[index] { return false }
        index += 1
      }
      return index == lowercase.utf8CodeUnitCount
    }
  }
}

/// Collects the attributes `StaticHTMLFiberRenderer.assembleAttributes` assembles: as (name, value) string indices when it
/// collects, and always as a hash of the names and values.
struct BinaryAttributeSink: HTMLAttributeSink {
  let strings: BinaryStrings
  /// The attributes of the element being assembled: name, value, name, value...
  var pairs: [UInt32] = []
  /// The hash of the names and values so far.
  var hash = BinaryHash.seed
  /// Set before assembling: the node id is not collected, because the element's handle and descriptor carry it.
  var dropsNodeID = false
  /// Set while collecting: the element holds something a shape cannot stand for (see `BinaryShapeTable`).
  var forbidsShape = false
  private var collects = true
  private var name: UInt32 = 0
  /// Whether the value being assembled is unique to the element (its node id, its event token): it is not looked up.
  private var unique = false
  /// The value being assembled.
  private var value = HTMLByteBuffer(capacity: 512)

  init(strings: BinaryStrings) { self.strings = strings }

  mutating func release() { value.deallocate() }

  mutating func start(collects: Bool) {
    self.collects = collects
    hash = BinaryHash.seed
    forbidsShape = false
    pairs.removeAll(keepingCapacity: true)
  }

  mutating func begin(name pointer: UnsafePointer<UInt8>, count: Int, in bytes: inout HTMLByteBuffer) {
    hash = BinaryHash.mix(hash, pointer, count: count)
    if collects {
      name = strings.intern(pointer, count: count)
      unique = name == BinaryAttributeSink.nodeIDAtom || name == BinaryAttributeSink.eventIDAtom
      value.truncate(to: 0)
    }
  }

  mutating func value(_ string: String, in bytes: inout HTMLByteBuffer) {
    if string.utf8.withContiguousStorageIfAvailable({ (buffer: UnsafeBufferPointer<UInt8>) -> Void in
      if let start = buffer.baseAddress { push(start, count: buffer.count) }
    }) != nil { return }
    var owned = string
    owned.withUTF8 { buffer in
      if let start = buffer.baseAddress { push(start, count: buffer.count) }
    }
  }

  mutating func value(bytes pointer: UnsafePointer<UInt8>, count: Int, in bytes: inout HTMLByteBuffer) { push(pointer, count: count) }

  mutating func separator(_ byte: UInt8, in bytes: inout HTMLByteBuffer) {
    hash = BinaryHash.mix(hash, UInt64(byte))
    if collects { value.append(byte) }
  }

  mutating func literal(_ text: StaticString, in bytes: inout HTMLByteBuffer) {
    hash = BinaryHash.mix(hash, text.utf8Start, count: text.utf8CodeUnitCount)
    if collects { value.append(text) }
  }

  mutating func end(in bytes: inout HTMLByteBuffer) {
    hash = BinaryHash.mix(hash, 0x01)
    guard collects else { return }
    if name == BinaryAttributeSink.nodeIDAtom && dropsNodeID { return }
    if name == BinaryAttributeSink.hoverRulesAtom || name == BinaryAttributeSink.webMountAtom || name == BinaryAttributeSink.domViewAtom { forbidsShape = true }
    if name == BinaryAttributeSink.hostManagedAtom && value.count >= 9 && value.base[0] == UInt8(ascii: "*") && value.base[1] == UInt8(ascii: "c") { forbidsShape = true }
    pairs.append(name)
    pairs.append(unique ? strings.appendUnique(value.base, count: value.count) : strings.intern(value.base, count: value.count))
  }

  /// An attribute the encoder adds (see `Placement`), assembled as the node's own are.
  mutating func extra(_ name: String, _ value: String) {
    var ownedName = name
    ownedName.withUTF8 { buffer in
      guard let base = buffer.baseAddress else { return }
      hash = BinaryHash.mix(hash, base, count: buffer.count)
      if collects { self.name = strings.intern(base, count: buffer.count); unique = false; self.value.truncate(to: 0) }
    }
    var ownedValue = value
    ownedValue.withUTF8 { buffer in if let base = buffer.baseAddress { push(base, count: buffer.count) } }
    hash = BinaryHash.mix(hash, 0x01)
    guard collects else { return }
    pairs.append(self.name)
    pairs.append(strings.intern(self.value.base, count: self.value.count))
  }

  /// A NUL separates the strings of a publication, so a value cannot hold one; the parser turns it into U+FFFD.
  private mutating func push(_ bytes: UnsafePointer<UInt8>, count: Int) {
    hash = BinaryHash.mix(hash, bytes, count: count)
    guard collects else { return }
    var runStart = 0
    var index = 0
    while index < count {
      if bytes[index] == 0 {
        value.append(bytes + runStart, count: index - runStart)
        value.append(0xEF)
        value.append(0xBF)
        value.append(0xBD)
        runStart = index + 1
      }
      index += 1
    }
    if runStart < count { value.append(bytes + runStart, count: count - runStart) }
  }

  /// The indices of the attributes whose values are never shared between elements.
  private static let nodeIDAtom: UInt32 = BinaryAtomTable.shared.index(of: "data-embedded-node-id")
  private static let eventIDAtom: UInt32 = BinaryAtomTable.shared.index(of: "data-embedded-event-id")
  private static let hoverRulesAtom: UInt32 = BinaryAtomTable.shared.index(of: "data-hover-rules")
  private static let webMountAtom: UInt32 = BinaryAtomTable.shared.index(of: "data-web-mount-key")
  private static let domViewAtom: UInt32 = BinaryAtomTable.shared.index(of: "data-dom-view")
  private static let hostManagedAtom: UInt32 = BinaryAtomTable.shared.index(of: "data-host-managed")
}
