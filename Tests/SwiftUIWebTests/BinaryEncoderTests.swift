import Foundation
import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebHTML
@testable import SwiftUIWebHTML
@testable import SwiftUIWeb

/// A binary publication read: its words, its strings, and the reference publication that rode along in the verification mode.
private struct BinaryStream {
  var words: [UInt32] = []
  var strings: [String] = []
  var ownCount = 0
  var reference: [UInt8]?
  var generation: UInt32 = 0

  init(_ bytes: [UInt8]) {
    func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24 }
    precondition(Array(bytes[0..<4]) == [0, 0x53, 0x57, 0x42], "no header")
    precondition(u16(4) == Int(_BinaryFormat.version) && u32(8) == _BinaryFormat.atomsHash, "format")
    let flags = u16(6)
    let wordCount = Int(u32(16)), count = Int(u32(20)), stringBytes = Int(u32(24))
    ownCount = count
    generation = u32(12)
    words = (0..<wordCount).map { u32(28 + $0 * 4) }
    let stringsStart = 28 + wordCount * 4
    let own = count == 0 ? [] : bytes[stringsStart..<(stringsStart + stringBytes)].split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
    precondition(own.count == count, "strings")
    if flags & 1 != 0 { reference = Array(bytes[(stringsStart + stringBytes)...]) }
    var atoms: [String] = []
    var current: [UInt8] = []
    for byte in _BinaryFormat.atoms.withUTF8Buffer({ Array($0) }) {
      if byte == 0 { atoms.append(String(decoding: current, as: UTF8.self)); current = [] } else { current.append(byte) }
    }
    atoms.append(String(decoding: current, as: UTF8.self))
    precondition(atoms.count == Int(_BinaryFormat.atomCount))
    strings = atoms + own
  }
}

/// One node of a list: an element (its handle and the descriptor of its id, namespace prefix, tag, attributes without the id,
/// and children), a text, or a held element.
private indirect enum ReadNode {
  case element(handle: String?, descriptor: String, tag: String, attributes: [(String, String)], children: [ReadNode])
  case text(String)
  case held(String)

  /// `<tag a="v">children</tag>`, the id among the attributes where its name sorts; a held element is `{i:g}`.
  var description: String {
    switch self {
    case .text(let text): return text
    case .held(let handle): return "{\(handle)}"
    case .element(let handle, let descriptor, let tag, let attributes, let children):
      var all = attributes
      if let handle {
        let at = all.firstIndex { $0.0 > "data-embedded-node-id" } ?? all.count
        all.insert(("data-embedded-node-id", "\(handle):\(descriptor)"), at: at)
      }
      return "<\(tag)" + all.map { " \($0.0)=\"\($0.1)\"" }.joined() + ">" + children.map(\.description).joined() + "</\(tag)>"
    }
  }

  /// The number of elements in it.
  var elementCount: Int {
    if case .element(_, _, _, _, let children) = self { return 1 + children.reduce(0) { $0 + $1.elementCount } }
    return 0
  }
}

/// The templates a page holds, for the generation of the table that defined them.
private final class DecodedTemplates {
  var map: [Int: ReadNode] = [:]
  var generation: UInt32 = 0
}

/// A binary publication read back into the nodes of a ROOT, or into its records. A shape is read as the nodes it builds.
private struct DecodedPublication {
  /// A ROOT: the nodes of the tree.
  var nodes: [ReadNode] = []
  var isRoot = false
  var stringCount = 0
  var reference: [UInt8]?
  /// Records: `ATTRS 3:1 a="v"` and `CHILDREN 3:1 <nodes>` (`root` for the page's own list).
  var records: [String] = []
  /// The shapes the publication defines (their ids), and the nodes it builds as shapes (their ids, in order).
  var definitions: [Int] = []
  var shapes: [Int] = []
  var generation: UInt32 = 0
  var wordCount = 0

  var description: String { nodes.map(\.description).joined() }
  var topLevel: Int { nodes.count }

  init(_ bytes: [UInt8], templates: DecodedTemplates = DecodedTemplates()) {
    let stream = BinaryStream(bytes)
    stringCount = stream.ownCount
    reference = stream.reference
    generation = stream.generation
    wordCount = stream.words.count
    if templates.generation != stream.generation { templates.map.removeAll(); templates.generation = stream.generation }
    let words = stream.words, strings = stream.strings
    var position = 0
    var definitions: [Int] = [], shapes: [Int] = []
    func handle(_ index: UInt32, _ generation: UInt32) -> String? { index == 0 ? nil : "\(index - 1):\(generation)" }
    func pairs() -> [(String, String)] {
      let count = Int(words[position]); position += 1
      var out: [(String, String)] = []
      for _ in 0..<count { out.append((strings[Int(words[position])], strings[Int(words[position + 1])])); position += 2 }
      return out
    }
    func list() -> [ReadNode] {
      var out: [ReadNode] = []
      while words[position] != _BinaryFormat.opEnd { if let made = node() { out.append(made) } }
      return out
    }
    /// A copy of a template with the handles of a shape and its fills.
    func instantiate(_ template: ReadNode, _ handles: inout [(String?, String)], _ fills: [Int: String], _ slot: inout Int) -> ReadNode {
      switch template {
      case .text(let text):
        defer { slot += 1 }
        return .text(fills[slot] ?? text)
      case .held: return template
      case .element(_, _, let tag, let attributes, let children):
        let (id, descriptor) = handles.removeFirst()
        var filled: [(String, String)] = []
        for (name, value) in attributes { filled.append((name, fills[slot] ?? value)); slot += 1 }
        return .element(handle: id, descriptor: descriptor, tag: tag, attributes: filled, children: children.map { instantiate($0, &handles, fills, &slot) })
      }
    }
    func node() -> ReadNode? {
      let word = words[position]; position += 1
      switch word {
      case _BinaryFormat.opHeld:
        let result = ReadNode.held(handle(words[position], words[position + 1]) ?? "none"); position += 2
        return result
      case _BinaryFormat.opText:
        let result = ReadNode.text(strings[Int(words[position])]); position += 1
        return result
      case _BinaryFormat.opDefine:
        let id = Int(words[position]); position += 1
        templates.map[id] = node()
        definitions.append(id)
        return nil
      case _BinaryFormat.opShape:
        let id = Int(words[position]), count = Int(words[position + 1]); position += 2
        var handles: [(String?, String)] = []
        for _ in 0..<count {
          handles.append((handle(words[position], words[position + 1]), strings[Int(words[position + 2])]))
          position += 3
        }
        let fillCount = Int(words[position]); position += 1
        var fills: [Int: String] = [:]
        for _ in 0..<fillCount { fills[Int(words[position])] = strings[Int(words[position + 1])]; position += 2 }
        guard let template = templates.map[id] else { preconditionFailure("shape \(id) was never defined") }
        precondition(template.elementCount == count, "shape \(id) has \(count) handles for \(template.elementCount) elements")
        var slot = 0
        shapes.append(id)
        return instantiate(template, &handles, fills, &slot)
      case _BinaryFormat.opElement, _BinaryFormat.opElementNs:
        let id = handle(words[position], words[position + 1]), descriptor = strings[Int(words[position + 2])]; position += 3
        var prefix = ""
        if word == _BinaryFormat.opElementNs { prefix = words[position] == _BinaryFormat.namespaceSvg ? "svg:" : "math:"; position += 1 }
        let tag = prefix + strings[Int(words[position])]; position += 1
        let attributes = pairs()
        let children = list()
        position += 1
        return .element(handle: id, descriptor: descriptor, tag: tag, attributes: attributes, children: children)
      default:
        preconditionFailure("unknown op \(word)")
      }
    }
    defer { self.definitions = definitions; self.shapes = shapes }
    if words.first == _BinaryFormat.opRoot {
      isRoot = true
      let count = Int(words[1])
      position = 2
      while nodes.count < count { if let made = node() { nodes.append(made) } }
      // Definitions after the last node are not possible: a definition comes before its first use.
      precondition(position == words.count, "words after the root")
      return
    }
    while position < words.count {
      let word = words[position]; position += 1
      switch word {
      case _BinaryFormat.opDefine:
        let id = Int(words[position]); position += 1
        templates.map[id] = node()
        definitions.append(id)
      case _BinaryFormat.opAttrs:
        let id = handle(words[position], words[position + 1]) ?? "root"; position += 2
        records.append("ATTRS \(id)" + pairs().map { " \($0.0)=\"\($0.1)\"" }.joined())
      case _BinaryFormat.opChildren:
        let id = handle(words[position], words[position + 1]) ?? "root"; position += 2
        let nodes = list()
        position += 1
        records.append("CHILDREN \(id) " + nodes.map(\.description).joined())
      default:
        preconditionFailure("unknown record \(word)")
      }
    }
  }
}

/// Encodes `root` for a host that holds nothing, and serializes it as the HTML transport does (the markup the page fixtures are
/// compared with). `attachReference` also attaches the reference publication of the same tree (the verification mode).
@MainActor
private func publish(_ root: _RenderNode, depth: Int? = nil, attachReference: Bool = false, shapes: BinaryShapeTable? = nil) -> (stream: [UInt8]?, html: String) {
  let renderer = StaticHTMLFiberRenderer(maxElementDepth: depth)
  return renderer.withRenderedUTF8(root) { bytes in
    let encoder = BinaryFiberEncoder(maxElementDepth: depth, acked: 0, covered: 1, rootRecord: BinaryNodeRecord(), shapes: shapes, lookup: { _ in nil })
    let reference = attachReference ? BinaryFiberEncoder(maxElementDepth: depth, acked: 0, covered: 1, rootRecord: BinaryNodeRecord(), lookup: { _ in nil }).encode(root)?.bytes : nil
    let output = reference.map { attached in attached.withUnsafeBufferPointer { encoder.encode(root, reference: $0) } } ?? encoder.encode(root)
    return (output?.bytes, String(decoding: bytes, as: UTF8.self))
  }
}

private typealias C = HTMLWriterCorpus

@Suite
@MainActor
struct BinaryEncoderTests {
  private func expectDescription(_ actual: String, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, "got: \(actual)", sourceLocation: sourceLocation)
  }

  private func describe(_ root: _RenderNode, depth: Int? = nil) -> String {
    DecodedPublication(publish(root, depth: depth).stream!).description
  }

  @Test
  func anElementIsItsTagItsSortedAttributesAndItsChildren() {
    let tree = C.element("div", ["title": "t&t", "data-embedded-node-id": "1:2:x"], classes: ["b", "a"], styles: ["z-index": "1", "color": "red"],
                         events: ["click": "tap"], [.text("hello <b>"), C.element("span", ["id": "s"], [.text("x")])])
    expectDescription(describe(tree), "<div class=\"b a\" data-embedded-node-id=\"1:2:x\" data-fiber-event-click=\"tap\" style=\"color: red; z-index: 1;\" title=\"t&t\">hello <b><span id=\"s\">x</span></div>")
  }

  @Test
  func theAttributesAreTheOnesTheMarkupWrites() {
    // Whatever the serializer writes for the node, the stream carries the same names, values and order.
    let transparent = C.element("div", ["data-layout-kind": "vstack", "class": "own"], classes: ["k"], styles: ["gap": "4px"], [.text("x")])
    let active = C.element("div", ["data-layout-kind": "vstack", "class": "own"], classes: ["k"], styles: ["gap": "4px"], events: ["click": "c", "appear": "a", "task": "t"], [.text("x")])
    for tree in [transparent, active] {
      expectDescription(describe(tree), StaticHTMLFiberRenderer().renderNode(tree))
    }
    expectDescription(describe(active), "<div class=\"own k\" data-fiber-event-click=\"c\" data-layout-kind=\"vstack\" style=\"gap: 4px;\">x</div>")
    // A hit-transparent layout container carries `passthrough`.
    expectDescription(describe(transparent), "<div class=\"own k passthrough\" data-layout-kind=\"vstack\" style=\"gap: 4px;\">x</div>")
  }

  @Test
  func fragmentsAreFlattenedAndEmptyNodesAndEmptyTextsAreDropped() {
    let tree = C.element("div", [:], [.empty(), C.fragment([.text("a"), C.fragment([.empty(), .text("b")])]), .text(""), C.fragment([]), C.element("br", [:], [.text("ignored")])])
    expectDescription(describe(tree), "<div>ab<br></br></div>")
    let publication = DecodedPublication(publish(C.fragment([.text("a"), .empty(), C.element("i"), .text("b")])).stream!)
    #expect(publication.topLevel == 3)
    #expect(publication.description == "a<i></i>b")
  }

  @Test
  func aTextWithAttributesIsASpanAndAPlainTextIsJustText() {
    let tree = C.element("div", [:], [C.text("one", classes: ["t"]), .text("two"), C.text("", ["title": "empty"])])
    expectDescription(describe(tree), "<div><span class=\"t\">one</span>two<span title=\"empty\"></span></div>")
  }

  @Test
  func svgAndMathMLElementsCarryTheirNamespaceAndHtmlComesBackInsideForeignObject() {
    let tree = C.element("div", [:], [
      C.element("svg", ["viewBox": "0 0 1 1"], [
        C.element("path", ["d": "M0 0"]),
        C.element("foreignObject", [:], [C.element("div", [:], [C.element("svg", [:], [C.element("circle")])]), C.element("circle")]),
        C.element("title", [:], [C.element("g")]),
        C.element("g", [:], [C.element("desc", [:], [C.element("rect")])]),
      ]),
      C.element("math", [:], [C.element("mi", [:], [C.element("b")]), C.element("mo")]),
      C.element("circle"),
    ])
    expectDescription(describe(tree), "<div><svg:svg viewBox=\"0 0 1 1\"><svg:path d=\"M0 0\"></svg:path>"
      + "<svg:foreignObject><div><svg:svg><svg:circle></svg:circle></svg:svg></div><circle></circle></svg:foreignObject>"
      + "<svg:title><g></g></svg:title><svg:g><svg:desc><rect></rect></svg:desc></svg:g></svg:svg>"
      + "<math:math><math:mi><b></b></math:mi><math:mo></math:mo></math:math><circle></circle></div>")
  }

  @Test
  func anElementPastTheNestingLimitIsClosedAtOnceAndItsChildrenFollowAsSiblings() {
    // Limit 3: the fourth element opens at depth 3, so it is closed at once and its child is its sibling.
    let tree = C.chain(6, leaf: "leaf", ids: false)
    expectDescription(describe(tree, depth: 3), "<div><div><div><div></div><div></div><div></div>leaf</div></div></div>")
    // Within the limit nothing changes.
    expectDescription(describe(C.chain(3, leaf: "leaf", ids: false), depth: 3), "<div><div><div>leaf</div></div></div>")
    // The children of a closed-at-once element are made in the namespace of its parent.
    let foreign = C.element("div", [:], [C.element("div", [:], [C.element("svg", [:], [C.element("path")])])])
    expectDescription(describe(foreign, depth: 2), "<div><div><svg:svg></svg:svg><path></path></div></div>")
  }

  @Test
  func textIsTakenAsItIsAndNulIsNotCarried() {
    let tree = C.element("p", ["title": "a\u{0}b"], [.text("x\u{0}y\r\nz"), .text(C.special)])
    expectDescription(describe(tree), "<p title=\"a\u{FFFD}b\">xy\r\nz&<>\"'</p>")
  }

  @Test
  func stringsAreSharedAndAtomsAreNeverCarried() {
    let rows = (0..<50).map { _ in C.element("div", ["data-layout-kind": "vstack", "data-custom-attribute-one": "same value"], classes: ["row"], [.text("same text")]) }
    let publication = DecodedPublication(publish(C.element("main", [:], rows)).stream!)
    // "data-custom-attribute-one", "same value" and "same text" are carried once; "div", "class", "row"... are atoms.
    #expect(publication.stringCount <= 4)
  }

  @Test
  func theStringsOfAnElementAreNotLookedUpWhenNoOtherElementCanShareThem() {
    // A node id and an event token belong to one element: they are carried as they come, and the strings that repeat are
    // carried once.
    let rows = (0..<40).map { index in
      C.element("div", ["data-embedded-node-id": "\(index):1:", "data-embedded-event-id": "\(index + 1000)", "title": "shared"], [.text("same")])
    }
    let publication = DecodedPublication(publish(C.element("main", [:], rows)).stream!)
    #expect(publication.stringCount == 2 + 1 + 40)
  }

  @Test
  func anElementIsNamedByTheHandleOfItsId() {
    let publication = DecodedPublication(publish(C.element("div", ["data-embedded-node-id": "7:3:main"], [C.element("span", ["data-embedded-node-id": "8:1:"]), C.element("i")])).stream!)
    guard case .element(let handle, _, _, _, let children) = publication.nodes[0] else { Issue.record("no element"); return }
    #expect(handle == "7:3")
    guard case .element(let second, _, _, _, _) = children[0], case .element(let third, _, _, _, _) = children[1] else { Issue.record("no children"); return }
    #expect(second == "8:1")
    // An element with no id of its own cannot be named again.
    #expect(third == nil)
  }

  @Test
  func theReferenceOfTheSameTreeRidesAlongWhenAsked() {
    let tree = C.element("div", ["id": "a"], [.text("hello")])
    let plain = publish(tree).stream!
    let attached = DecodedPublication(publish(tree, attachReference: true).stream!)
    // The reference is the publication of the tree as a fresh encoder makes it, a complete one of its own, and the publication
    // carries the same tree as it would without it.
    #expect(attached.reference == plain)
    #expect(DecodedPublication(attached.reference!).description == attached.description)
    #expect(attached.description == DecodedPublication(plain).description)
    #expect(DecodedPublication(plain).reference == nil)
  }

  // MARK: What the parser would restructure

  private func written(_ root: _RenderNode) -> String? { publish(root).stream.map { DecodedPublication($0).description } }

  @Test
  func aTreeTheParserWouldRestructureIsWrittenAsOneItKeeps() {
    func e(_ tag: String, _ children: [_RenderNode] = []) -> _RenderNode { C.element(tag, [:], children) }
    let table = { (cell: String) in "<table><tbody><tr><td>\(cell)</td></tr></tbody></table>" }
    let placed: [(String, _RenderNode, String)] = [
      ("a form in a form", e("form", [e("div", [e("form")])]), "<form><div><div role=\"form\"></div></div></form>"),
      ("a link in a link", e("a", [e("span", [e("a")])]), "<a><span><span role=\"link\"></span></span></a>"),
      ("a div in a p", e("p", [e("span", [e("div")])]), "<div role=\"paragraph\"><span><div></div></span></div>"),
      ("a list in a p", e("div", [e("p", [e("ul")])]), "<div><div role=\"paragraph\"><ul></ul></div></div>"),
      ("a heading in a p", e("p", [e("h2")]), "<div role=\"paragraph\"><h2></h2></div>"),
      ("a li in a li", e("ul", [e("li", [e("span", [e("li")])])]), "<ul><li><span><div role=\"listitem\"></div></span></li></ul>"),
      ("a li in a li behind a div", e("li", [e("div", [e("li")])]), "<li><div><div role=\"listitem\"></div></div></li>"),
      ("a dd after a dt", e("dl", [e("dt", [e("dd")])]), "<dl><dt><div></div></dt></dl>"),
      ("a heading in a heading", e("h1", [e("h2")]), "<h1><div role=\"heading\" aria-level=\"2\"></div></h1>"),
      ("an option in an option", e("select", [e("option", [e("option")])]), "<select><option></option></select>"),
      ("an optgroup in an option", e("select", [e("option", [e("optgroup")])]), "<select><option></option></select>"),
      ("a div in a select", e("select", [e("div")]), "<select><option></option></select>"),
      ("a span in an option", e("select", [e("option", [e("span", [.text("label")])])]), "<select><option>label</option></select>"),
      ("a td outside a row", e("div", [e("td")]), "<div>\(table(""))</div>"),
      ("a tr outside a table", e("tr"), "<table><tbody><tr></tr></tbody></table>"),
      ("a tr in a table", e("table", [e("tr", [e("td")])]), table("")),
      ("a td in a tbody", e("table", [e("tbody", [e("td")])]), table("")),
      ("a div in a row", e("table", [e("tbody", [e("tr", [e("div")])])]), table("<div></div>")),
      ("a div in a table", e("table", [e("div")]), table("<div></div>")),
      ("a table in a table", e("table", [e("table")]), table("<table></table>")),
      ("a table in a row", e("table", [e("tbody", [e("tr", [e("table")])])]), table("<table></table>")),
      ("a col outside a colgroup", e("table", [e("col")]), "<table><colgroup><col></col></colgroup></table>"),
      ("text in a table", e("table", [e("tbody", [e("tr", [.text("x")])])]), table("x")),
      ("a nobr in a nobr", e("nobr", [e("b", [e("nobr")])]), "<nobr><b><span></span></b></nobr>"),
      ("a body", e("div", [e("body")]), "<div><div></div></div>"),
      ("a div in svg", e("svg", [e("g", [e("div")])]), "<svg:svg><svg:g><svg:g></svg:g></svg:g></svg:svg>"),
      ("a span in svg", e("svg", [C.text("t", classes: ["c"])]), "<svg:svg><svg:tspan class=\"c\">t</svg:tspan></svg:svg>"),
      ("a p in math", e("math", [e("p")]), "<math:math><math:mrow></math:mrow></math:math>"),
      ("a TD outside a row", e("div", [e("TD")]), "<div><table><tbody><tr><TD></TD></tr></tbody></table></div>"),
    ]
    for (name, tree, expected) in placed { #expect(written(tree) == expected, "\(name): \(written(tree) ?? "nil")") }
    // A tree the parser keeps is written as it is: as its markup, once the description's namespaces and the end tags of void
    // elements are left out.
    func markup(_ description: String?) -> String? {
      description.map { $0.replacingOccurrences(of: "svg:", with: "").replacingOccurrences(of: "math:", with: "").replacingOccurrences(of: "</col>", with: "").replacingOccurrences(of: "</hr>", with: "") }
    }
    let kept: [(String, _RenderNode)] = [
      ("a form once", e("form", [e("div", [e("button")])])),
      ("a link in a div in a link-free tree", e("div", [e("a", [e("span")]), e("a")])),
      ("spans and links in a p", e("p", [e("span", [e("a"), e("b")]), e("em")])),
      ("a list in a list", e("ul", [e("li", [e("ul", [e("li"), e("li")])]), e("li")])),
      ("a li in a div in an ol", e("ol", [e("li", [e("div", [e("ol", [e("li")])])])])),
      ("definitions", e("dl", [e("dt"), e("dd"), e("dt"), e("dd")])),
      ("headings side by side", e("div", [e("h1"), e("h2", [e("span")])])),
      ("a select with groups", e("select", [e("optgroup", [e("option"), e("option")]), e("option"), e("hr")])),
      ("a whole table", e("table", [e("caption"), e("colgroup", [e("col")]), e("thead", [e("tr", [e("th")])]), e("tbody", [e("tr", [e("td", [e("div", [e("table")])])])]), e("tfoot")])),
      ("white space in a table", e("table", [e("tbody", [.text(" \n")])])),
      ("a button with a p after a p", e("div", [e("p"), e("p")])),
      ("a form in a td", e("form", [e("span")])),
      ("svg with html in foreignObject", e("svg", [e("foreignObject", [e("div", [e("p", [e("span")])])])])),
      ("a TD where it belongs", e("table", [e("tbody", [e("TR", [e("TD")])])])),
      ("text with attributes in a div", e("div", [C.text("t", classes: ["c"])])),
    ]
    for (name, tree) in kept { #expect(markup(written(tree)) == publish(tree).html, "\(name): \(written(tree) ?? "nil") against \(publish(tree).html)") }
  }

  // MARK: Records

  /// A publisher for hand-built trees, which stands where `BrowserApp` does: it remembers the record of every element by its
  /// id, and the trees the tests pass it say what the host holds by leaving the unchanged elements out as placeholders.
  private final class Publisher {
    var records: [String: BinaryNodeRecord] = [:]
    var root = BinaryNodeRecord()
    var acked: UInt64 = 0
    var epoch: UInt64 = 0
    var shapes: BinaryShapeTable?
    let templates = DecodedTemplates()

    @MainActor
    func publish(_ tree: _RenderNode) -> DecodedPublication? {
      epoch += 1
      let known = records
      let encoder = BinaryFiberEncoder(maxElementDepth: nil, acked: acked, covered: epoch, rootRecord: root, shapes: shapes, lookup: { node in
        node.attributes["data-embedded-node-id"].flatMap { known[$0] }
      })
      guard let output = encoder.encode(tree) else { return nil }
      for update in output.updates {
        if let id = update.node.attributes["data-embedded-node-id"] { records[id] = update.record }
      }
      root = output.rootRecord
      if firstBytes.isEmpty { firstBytes = output.bytes }
      history.append(output.bytes)
      bytes = output.bytes
      return DecodedPublication(output.bytes, templates: templates)
    }

    var bytes: [UInt8] = []
    var firstBytes: [UInt8] = []
    var history: [[UInt8]] = []
  }

  @MainActor
  private func element(_ id: String, _ tag: String = "div", _ attributes: KeyValuePairs<String, String> = [:], _ children: [_RenderNode] = []) -> _RenderNode {
    let node = C.element(tag, attributes, children)
    node.attributes["data-embedded-node-id"] = id
    return node
  }

  /// What a snapshot leaves of an element the host holds and that did not change.
  @MainActor
  private func placeholder(_ id: String, _ tag: String = "div") -> _RenderNode {
    C.element("keep", ["data-embedded-node-id": id, "data-keep-tag": tag])
  }

  /// A heading and a list of items; the elements named in `kept` are left out as the host holds them.
  @MainActor
  private func page(title: String = "t", items: [String] = ["a", "b"], keeping kept: Set<String> = []) -> _RenderNode {
    func maybe(_ id: String, _ tag: String, _ make: () -> _RenderNode) -> _RenderNode { kept.contains(id) ? placeholder(id, tag) : make() }
    return C.fragment([
      element("1:1:page", "main", [:], [
        maybe("2:1:", "h1") { element("2:1:", "h1", ["title": title], [.text(title)]) },
        maybe("3:1:", "ul") {
          element("3:1:", "ul", [:], items.enumerated().map { index, name in
            maybe("1\(index):1:", "li") { element("1\(index):1:", "li", ["data-name": name], [.text(name)]) }
          })
        },
      ]),
    ])
  }

  @Test
  func aHostThatHoldsNothingGetsTheWholeTreeAgainUntilItAcknowledges() throws {
    let publisher = Publisher()
    let first = try #require(publisher.publish(page()))
    #expect(first.isRoot)
    // Nothing is acknowledged: a second publication is a root again, whatever changed.
    let second = try #require(publisher.publish(page(title: "u")))
    #expect(second.isRoot)
    // The host acknowledged the second: it is told what changed in the third.
    publisher.acked = 2
    let third = try #require(publisher.publish(page(title: "v", keeping: ["3:1:"])))
    #expect(!third.isRoot)
    // An acknowledgement of the first alone is not enough: the host may have dropped the second.
    let other = Publisher()
    _ = other.publish(page())
    other.acked = 1
    _ = other.publish(page(title: "u"))
    other.acked = 1
    #expect(try #require(other.publish(page(title: "v", keeping: ["3:1:"]))).isRoot == false)
  }

  @Test
  func aHostThatAlwaysAcknowledgesOnePublicationLateIsNotSentTheWholeTreeAgainAndAgain() throws {
    let publisher = Publisher()
    _ = publisher.publish(page())
    // The second is a root too (the first is not acknowledged yet), and it carries the same tree: the host that acknowledges
    // the first holds all of what the second carried.
    _ = publisher.publish(page())
    publisher.acked = 1
    let third = try #require(publisher.publish(page(title: "u", keeping: ["3:1:"])))
    #expect(!third.isRoot)
    publisher.acked = 2
    #expect(try #require(publisher.publish(page(title: "v", keeping: ["3:1:"]))).isRoot == false)
  }

  @Test
  func whatIsHeldAndUnchangedCostsNothing() throws {
    let publisher = Publisher()
    _ = publisher.publish(page())
    publisher.acked = 1
    // The page is visited, the heading and the list are not.
    let unchanged = try #require(publisher.publish(page(keeping: ["2:1:", "3:1:"])))
    #expect(unchanged.records.isEmpty)
    #expect(publisher.bytes.count == 28)
  }

  @Test
  func anAttributeChangeIsAnAttrsRecordAndNothingElse() throws {
    func list(_ name: String, kept: Bool = false) -> _RenderNode {
      C.fragment([element("1:1:", "main", [:], [kept ? placeholder("2:1:", "p") : element("2:1:", "p", ["data-name": name], [.text("same")]), placeholder("3:1:", "p")])])
    }
    let publisher = Publisher()
    _ = publisher.publish(C.fragment([element("1:1:", "main", [:], [element("2:1:", "p", ["data-name": "a"], [.text("same")]), element("3:1:", "p", [:], [.text("other")])])]))
    publisher.acked = 1
    let changed = try #require(publisher.publish(list("b")))
    #expect(changed.records == ["ATTRS 2:1 data-name=\"b\""])
    // The text of a heading is its list of children: the heading's attributes are not told again when only the text changed.
    let again = Publisher()
    _ = again.publish(page())
    again.acked = 1
    let both = try #require(again.publish(page(title: "u", keeping: ["3:1:"])))
    #expect(both.records == ["ATTRS 2:1 title=\"u\"", "CHILDREN 2:1 u"])
  }

  @Test
  func aChangedListOfChildrenIsAChildrenRecordWithHeldElementsAndNewOnes() throws {
    let publisher = Publisher()
    _ = publisher.publish(page(items: ["a", "b"]))
    publisher.acked = 1
    let longer = try #require(publisher.publish(page(items: ["a", "b", "c"], keeping: ["2:1:", "10:1:", "11:1:"])))
    #expect(longer.records == ["CHILDREN 3:1 {10:1}{11:1}<li data-embedded-node-id=\"12:1:\" data-name=\"c\">c</li>"])
    // The new element is held once the host acknowledged the publication that built it.
    publisher.acked = 2
    let same = try #require(publisher.publish(page(items: ["a", "b", "c"], keeping: ["2:1:", "10:1:", "11:1:", "12:1:"])))
    #expect(same.records.isEmpty)
    // A removed element is simply not listed.
    let shorter = try #require(publisher.publish(page(items: ["a", "b"], keeping: ["2:1:", "10:1:", "11:1:"])))
    #expect(shorter.records == ["CHILDREN 3:1 {10:1}{11:1}"])
  }

  @Test
  func anElementTheHostDidNotAcknowledgeIsBuiltAgain() throws {
    let publisher = Publisher()
    _ = publisher.publish(page(items: ["a"]))
    publisher.acked = 1
    let added = try #require(publisher.publish(page(items: ["a", "b"], keeping: ["2:1:", "10:1:"])))
    #expect(added.records.count == 1)
    // The host dropped that publication: still acknowledging the first, it is told again, and the element is built again.
    let again = try #require(publisher.publish(page(items: ["a", "b"], keeping: ["2:1:", "10:1:"])))
    #expect(again.records == added.records)
    // It acknowledged the third publication, which carried the same: nothing is left to say.
    publisher.acked = 3
    let settled = try #require(publisher.publish(page(items: ["a", "b"], keeping: ["2:1:", "3:1:"])))
    #expect(settled.records.isEmpty)
  }

  @Test
  func theHostKeepsStateInAControlSoItsAttributesAreWrittenAgainWithWhateverElseChanges() throws {
    func form(_ text: String, keepingParagraph: Bool) -> _RenderNode {
      C.fragment([element("1:1:", "form", [:], [element("2:1:", "input", ["type": "text", "value": "v"]), keepingParagraph ? placeholder("3:1:", "p") : element("3:1:", "p", [:], [.text(text)])])])
    }
    let publisher = Publisher()
    _ = publisher.publish(form("x", keepingParagraph: false))
    publisher.acked = 1
    // Nothing changed: nothing is sent, as the markup of an unchanged page is not applied.
    #expect(try #require(publisher.publish(form("x", keepingParagraph: true))).records.isEmpty)
    publisher.acked = publisher.epoch
    // Something did: the control's state is written again with it, so a typed value that Swift does not hold is put back.
    let changed = try #require(publisher.publish(form("y", keepingParagraph: false)))
    #expect(changed.records == ["CHILDREN 3:1 y", "ATTRS 2:1 type=\"text\" value=\"v\""])
  }

  @Test
  func anElementThatMovedToAnotherParentIsListedThereAsHeld() throws {
    func list(_ id: String, _ items: [String]) -> _RenderNode { element(id, "ul", [:], items.map { element($0, "li", [:], [.text($0)]) }) }
    let publisher = Publisher()
    _ = publisher.publish(C.fragment([element("1:1:", "main", [:], [list("2:1:", ["10:1:", "11:1:"]), list("3:1:", [])])]))
    publisher.acked = 1
    let next = C.fragment([element("1:1:", "main", [:], [element("2:1:", "ul", [:], [placeholder("10:1:", "li")]), element("3:1:", "ul", [:], [placeholder("11:1:", "li")])])])
    let published = try #require(publisher.publish(next))
    #expect(Set(published.records) == ["CHILDREN 2:1 {10:1}", "CHILDREN 3:1 {11:1}"])
  }

  @Test
  func aPlaceholderForAnElementOfAnotherIdentityIsDeclined() {
    let publisher = Publisher()
    _ = publisher.publish(page())
    publisher.acked = 1
    // The host holds a `ul`; a placeholder that says `ol` is not it.
    #expect(publisher.publish(C.fragment([element("1:1:page", "main", [:], [placeholder("2:1:", "h1"), placeholder("3:1:", "ol")])])) == nil)
    // And one whose handle the publisher never saw is not held at all.
    #expect(publisher.publish(C.fragment([element("1:1:page", "main", [:], [placeholder("2:1:", "h1"), placeholder("9:1:", "ul")])])) == nil)
  }

  @Test
  func aPlaceholderIsCheckedAgainstWhatTheParserKeeps() throws {
    let publisher = Publisher()
    _ = publisher.publish(C.fragment([element("1:1:", "div", [:], [element("2:1:", "a", [:], [.text("x")])])]))
    publisher.acked = 1
    // A `p` holding an element the host holds is a neutral block (what is below the placeholder is not visited), and the
    // element stays held in it.
    let paragraph = try #require(publisher.publish(C.fragment([element("1:1:", "p", [:], [placeholder("2:1:", "a")])])))
    #expect(paragraph.records == ["ATTRS 1:1 role=\"paragraph\""])
    publisher.acked = 2
    // A link in a link is written as a `span`: the host's `a` is not what it would be given, so the publication is the whole tree.
    #expect(publisher.publish(C.fragment([element("3:1:", "a", [:], [placeholder("2:1:", "a")])])) == nil)
  }

  // MARK: Shapes

  /// A row of four elements: the structure a shape stands for, with values of its own.
  @MainActor
  private func row(_ index: Int, text: String = "t", extra: [_RenderNode] = [], skeleton: String = "a") -> _RenderNode {
    let base = 20 + index * 10
    return element("\(base):1:", "li", ["data-name": "n\(index)", "data-\(skeleton)": "x"], [
      element("\(base + 1):1:", "span", ["class": "a"], [.text(text)]),
      element("\(base + 2):1:", "span", ["title": "x\(index)"], [.text("b")]),
      element("\(base + 3):1:", "button", [:], [.text("go")]),
    ] + extra)
  }

  @MainActor
  private func list(_ rows: [_RenderNode]) -> _RenderNode { C.fragment([element("1:1:", "ul", [:], rows)]) }

  @MainActor
  private func shaping(_ table: BinaryShapeTable = BinaryShapeTable(instancesBeforeDefinition: 2)) -> Publisher {
    let publisher = Publisher()
    publisher.shapes = table
    return publisher
  }

  @Test
  func aRepeatedSubtreeIsDefinedOnceItHasRepeatedEnoughAndAllOfItsInstancesAreShapes() throws {
    let rows = (0..<5).map { row($0, text: "t\($0)") }
    let publisher = shaping()
    let shaped = try #require(publisher.publish(list(rows)))
    // Five rows of a skeleton are enough to define it, and all five are built from it.
    #expect(shaped.definitions == [0])
    #expect(shaped.shapes == [0, 0, 0, 0, 0])
    // What it builds is what the rows are, and it is smaller than the rows written out.
    let plain = try #require(DecodedPublication(publish(list((0..<5).map { row($0, text: "t\($0)") })).stream!))
    #expect(shaped.description == plain.description)
    #expect(shaped.wordCount < plain.wordCount)
  }

  @Test
  func aShapeCarriesTheValuesThatDifferFromItsTemplate() throws {
    // Only the text of the first span differs between the rows, and the attribute of the second one.
    let rows = (0..<4).map { row($0, text: "t\($0)") }
    let published = try #require(shaping().publish(list(rows)))
    #expect(published.shapes.count == 4)
    // In every row the id, the descriptor and the values a row names itself differ: the fills are those.
    let expected = try #require(DecodedPublication(publish(list(rows)).stream!))
    #expect(published.description == expected.description)
  }

  @Test
  func whatIsNotForAShapeIsBuiltInFull() throws {
    func rows(_ make: (Int) -> _RenderNode) -> _RenderNode { list((0..<4).map(make)) }
    let cases: [(String, _RenderNode)] = [
      ("a control inside", rows { self.row($0, extra: [self.element("\(900 + $0):1:", "input", ["type": "text"])]) }),
      ("a host-owned container", rows { self.row($0, extra: [self.element("\(900 + $0):1:", "div", ["data-keep-lazy-index": "0"])]) }),
      ("host content", rows { self.row($0, extra: [self.element("\(900 + $0):1:", "div", ["data-host-managed": "*children"])]) }),
      ("two texts in a row", rows { self.element("\(20 + $0 * 10):1:", "li", [:], [self.element("\(21 + $0 * 10):1:", "span", [:], [.text("a"), .text("b")]), self.element("\(22 + $0 * 10):1:", "b"), self.element("\(23 + $0 * 10):1:", "i"), self.element("\(24 + $0 * 10):1:", "u")]) }),
      ("a text that keeps its first line feed", rows { self.row($0, extra: [self.element("\(900 + $0):1:", "pre", [:], [.text("x")])]) }),
      ("an element without an id", rows { self.row($0, extra: [C.element("b")]) }),
      ("too few elements", rows { self.element("\(20 + $0 * 10):1:", "li", [:], [self.element("\(21 + $0 * 10):1:", "span", [:], [.text("a")])]) }),
    ]
    for (name, tree) in cases {
      let published = try #require(shaping().publish(tree), "\(name)")
      #expect(published.definitions.isEmpty && published.shapes.isEmpty, "\(name) was built as a shape")
    }
  }

  @Test
  func aSubtreeWithAnElementTheHostHoldsIsNotAShape() throws {
    let publisher = shaping()
    func tree(keeping: Bool) -> _RenderNode {
      list((0..<4).map { index in row(index, extra: [keeping ? placeholder("\(900 + index):1:", "i") : element("\(900 + index):1:", "i")]) })
    }
    _ = publisher.publish(tree(keeping: false))
    publisher.acked = 1
    let published = try #require(publisher.publish(C.fragment([element("1:1:", "ul", [:], (0..<4).map { index in row(index, extra: [placeholder("\(900 + index):1:", "i")]) })])))
    #expect(published.shapes.isEmpty)
  }

  @Test
  func aDefinitionIsSentAgainUntilTheHostAcknowledgesIt() throws {
    let publisher = shaping()
    let first = try #require(publisher.publish(list([row(0)])))
    // One row is only counted. The host acknowledged the first publication; two rows are added.
    #expect(first.definitions.isEmpty)
    publisher.acked = 1
    let second = try #require(publisher.publish(C.fragment([element("1:1:", "ul", [:], [placeholder("20:1:", "li"), row(1), row(2)])])))
    #expect(second.definitions == [0])
    #expect(second.shapes == [0, 0])
    // The host dropped it: it is defined again, with the template it was defined with, and a page that only applies this one
    // ends where the other would.
    let third = try #require(publisher.publish(C.fragment([element("1:1:", "ul", [:], [placeholder("20:1:", "li"), row(1), row(2), row(3, text: "other")])])))
    #expect(third.definitions == [0])
    #expect(third.shapes == [0, 0, 0])
    let page = Page()
    page.apply(publisher.firstBytes)
    page.apply(publisher.bytes)
    #expect(page.failed == nil)
    #expect(page.description().contains("other"))
    // It acknowledged the third publication, which carried the definition: the next one needs none.
    publisher.acked = 3
    let fourth = try #require(publisher.publish(C.fragment([element("1:1:", "ul", [:], [placeholder("20:1:", "li"), placeholder("30:1:", "li"), placeholder("40:1:", "li"), placeholder("50:1:", "li"), row(4), row(5)])])))
    #expect(fourth.definitions.isEmpty)
    #expect(fourth.shapes == [0, 0])
  }

  @Test
  func aShapeIsTheSameTemplateWhicheverPublicationDefinedItAgain() throws {
    let publisher = shaping()
    _ = publisher.publish(list([row(0, text: "first")]))
    publisher.acked = 1
    _ = publisher.publish(C.fragment([element("1:1:", "ul", [:], [placeholder("20:1:", "li"), row(1, text: "second"), row(2, text: "third")])]))
    let lagging = Page()
    lagging.apply(publisher.firstBytes)
    // A later publication redefines it while the host has not acknowledged: the template is the one of the definition, not of
    // the rows this publication builds.
    _ = publisher.publish(C.fragment([element("1:1:", "ul", [:], [placeholder("20:1:", "li"), row(1, text: "second"), row(2, text: "third"), row(3, text: "fourth"), row(4, text: "fifth")])]))
    lagging.apply(publisher.bytes)
    #expect(lagging.failed == nil)
    let expected = DecodedPublication(publish(C.fragment([element("1:1:", "ul", [:], [row(0, text: "first"), row(1, text: "second"), row(2, text: "third"), row(3, text: "fourth"), row(4, text: "fifth")])])).stream!)
    #expect(lagging.description() == expected.description)
  }

  @Test
  func aPendingDefinitionIsCarriedByEveryPublicationEvenWhenItIsNotUsed() throws {
    func page(_ title: String, rows: [_RenderNode], kept: [String] = []) -> _RenderNode {
      C.fragment([element("1:1:", "ul", ["title": title], kept.map { placeholder($0, "li") } + rows)])
    }
    let publisher = shaping()
    _ = publisher.publish(page("a", rows: [row(0)]))
    publisher.acked = 1
    // The rows are added, and the shape is defined: the host drops this publication.
    let defining = try #require(publisher.publish(page("a", rows: [row(1), row(2)], kept: ["20:1:"])))
    #expect(defining.definitions == [0])
    // The next publication does not use the shape, and still carries its definition: the host acknowledges this one and not the
    // one before.
    let between = try #require(publisher.publish(page("b", rows: [], kept: ["20:1:"])))
    #expect(between.definitions == [0] && between.shapes.isEmpty)
    publisher.acked = publisher.epoch
    // The shape is held now, and used without a definition by the next rows.
    let later = try #require(publisher.publish(page("b", rows: [row(3), row(4)], kept: ["20:1:"])))
    #expect(later.definitions.isEmpty && later.shapes == [0, 0])
    let lagging = Page()
    lagging.apply(publisher.history[0])
    lagging.apply(publisher.history[2])
    lagging.apply(publisher.history[3])
    #expect(lagging.failed == nil)
    #expect(lagging.description().contains("n3") && lagging.description().contains("n4"))
  }

  @Test
  func theLeastRecentlyUsedShapeGivesUpItsId() throws {
    let table = BinaryShapeTable(capacity: 2, instancesBeforeDefinition: 2)
    let publisher = shaping(table)
    func group(_ skeleton: String, _ base: Int) -> [_RenderNode] { [row(base, skeleton: skeleton), row(base + 1, skeleton: skeleton)] }
    // Three skeletons twice each: the third finds no id it may take, because the other two are in use in this publication.
    let first = try #require(publisher.publish(list(group("a", 0) + group("b", 2) + group("c", 4))))
    #expect(first.definitions == [0, 1])
    #expect(table.definedCount == 2)
    // The next publication needs the third: the least recently used of the others gives its id up.
    let second = try #require(publisher.publish(list(group("c", 4) + group("c", 6))))
    // The other shape is not acknowledged yet, so it is carried again.
    #expect(second.definitions == [0, 1])
    #expect(second.shapes.count == 4)
  }

  @Test
  func aNewGenerationOfTheTableMakesThePageForgetWhatItHolds() throws {
    let table = BinaryShapeTable(instancesBeforeDefinition: 2)
    let publisher = shaping(table)
    let first = try #require(publisher.publish(list((0..<3).map { row($0) })))
    #expect(first.definitions == [0] && first.generation == 0)
    table.reset()
    publisher.acked = 0
    let second = try #require(publisher.publish(list((0..<3).map { row($0) })))
    #expect(second.generation == 1)
    #expect(second.definitions == [0])
    // A publication the encoder gives up on for the whole tree tells the page nothing, so the table starts again.
    let generation = table.generation
    _ = publisher.publish(C.fragment([element("1:1:", "div", [:], [element("2:1:", "a")])]))
    publisher.acked = publisher.epoch
    #expect(publisher.publish(C.fragment([element("3:1:", "a", [:], [placeholder("2:1:", "a")])])) == nil)
    #expect(table.generation == generation &+ 1)
  }

  // MARK: The host's view of the publications

  /// A model of the page: the elements it built by handle (it keeps every one), the list of children of each, and the list of
  /// the page itself. A record that names an element the page does not hold is a failure: the page would ask for a
  /// publication in full.
  private final class Page {
    final class Node {
      var tag: String
      var attributes: [String: String]
      var children: [Child] = []
      init(tag: String, attributes: [String: String]) { self.tag = tag; self.attributes = attributes }
    }
    enum Child { case text(String); case node(String) }
    /// A template the page holds: the values of an element in the order a shape names them.
    indirect enum Template {
      case element(tag: String, attributes: [(String, String)], children: [Template])
      case text(String)
    }

    var nodes: [String: Node] = [:]
    var top: [Child] = []
    var failed: String?
    var templates: [Int: Template] = [:]
    var generation: UInt32 = 0
    var shapesBuilt = 0

    func apply(_ bytes: [UInt8]) {
      let stream = BinaryStream(bytes)
      let words = stream.words, strings = stream.strings
      if stream.generation != generation { templates.removeAll(); generation = stream.generation }
      var position = 0
      func key(_ index: UInt32, _ generation: UInt32) -> String { "\(index &- 1):\(generation)" }
      func pairs() -> [(String, String)] {
        let count = Int(words[position]); position += 1
        var out: [(String, String)] = []
        for _ in 0..<count { out.append((strings[Int(words[position])], strings[Int(words[position + 1])])); position += 2 }
        return out
      }
      /// The element of a definition, without handles.
      func template() -> Template {
        let word = words[position]; position += 1
        switch word {
        case _BinaryFormat.opText:
          let text = strings[Int(words[position])]; position += 1
          return .text(text)
        default:
          position += 3
          if word == _BinaryFormat.opElementNs { position += 1 }
          let tag = strings[Int(words[position])]; position += 1
          let attributes = pairs()
          var children: [Template] = []
          while words[position] != _BinaryFormat.opEnd { children.append(template()) }
          position += 1
          return .element(tag: tag, attributes: attributes, children: children)
        }
      }
      // A list of nodes up to the END that closes it, or `count` top-level nodes (a root).
      func list(count: Int?) -> [Child] {
        var out: [Child] = []
        var read = 0
        while position < words.count {
          if let count { if read == count { break } } else if words[position] == _BinaryFormat.opEnd { break }
          read += 1
          let word = words[position]; position += 1
          switch word {
          case _BinaryFormat.opText:
            let text = strings[Int(words[position])]; position += 1
            if case .text(let before)? = out.last { out[out.count - 1] = .text(before + text) } else { out.append(.text(text)) }
          case _BinaryFormat.opHeld:
            let id = key(words[position], words[position + 1]); position += 2
            if nodes[id] == nil { failed = "held \(id) is not a node of the page" }
            out.append(.node(id))
          case _BinaryFormat.opDefine:
            read -= 1
            let id = Int(words[position]); position += 1
            templates[id] = template()
          case _BinaryFormat.opShape:
            let id = Int(words[position]), count = Int(words[position + 1]); position += 2
            var handles: [(String, String)] = []
            for _ in 0..<count {
              handles.append((key(words[position], words[position + 1]), strings[Int(words[position + 2])]))
              position += 3
            }
            let fillCount = Int(words[position]); position += 1
            var fills: [Int: String] = [:]
            for _ in 0..<fillCount { fills[Int(words[position])] = strings[Int(words[position + 1])]; position += 2 }
            guard let held = templates[id] else { failed = "shape \(id), which the page does not hold"; return out }
            var slot = 0
            func build(_ template: Template) -> Child {
              switch template {
              case .text(let text):
                defer { slot += 1 }
                return .text(fills[slot] ?? text)
              case .element(let tag, let attributes, let children):
                let (handle, descriptor) = handles.removeFirst()
                var made: [String: String] = ["data-embedded-node-id": "\(handle):\(descriptor)"]
                for (name, value) in attributes { made[name] = fills[slot] ?? value; slot += 1 }
                let node = Node(tag: tag, attributes: made)
                nodes[handle] = node
                node.children = children.map(build)
                return .node(handle)
              }
            }
            shapesBuilt += 1
            out.append(build(held))
          default:
            let id = key(words[position], words[position + 1]), descriptor = strings[Int(words[position + 2])]; position += 3
            if word == _BinaryFormat.opElementNs { position += 1 }
            let tag = strings[Int(words[position])]; position += 1
            var attributes: [String: String] = [:]
            for (name, value) in pairs() { attributes[name] = value }
            attributes["data-embedded-node-id"] = "\(id):\(descriptor)"
            let node = Node(tag: tag, attributes: attributes)
            nodes[id] = node
            node.children = list(count: nil)
            position += 1
            out.append(.node(id))
          }
        }
        return out
      }
      if words.first == _BinaryFormat.opRoot {
        position = 2
        top = list(count: Int(words[1]))
        return
      }
      while position < words.count, failed == nil {
        let word = words[position]; position += 1
        if word == _BinaryFormat.opDefine {
          let id = Int(words[position]); position += 1
          templates[id] = template()
          continue
        }
        let index = words[position], generation = words[position + 1]; position += 2
        if word == _BinaryFormat.opAttrs {
          guard let node = nodes[key(index, generation)] else { failed = "attributes of \(key(index, generation)), which the page does not hold"; return }
          // The id belongs to the handle: it is not in the record.
          var attributes: [String: String] = [:]
          for (name, value) in pairs() { attributes[name] = value }
          attributes["data-embedded-node-id"] = node.attributes["data-embedded-node-id"]
          node.attributes = attributes
        } else {
          let children = list(count: nil)
          position += 1
          if index == 0 { top = children }
          else if let node = nodes[key(index, generation)] { node.children = children }
          else { failed = "children of \(key(index, generation)), which the page does not hold" }
        }
      }
    }

    func description() -> String { top.map(describe).joined() }

    private func describe(_ child: Child) -> String {
      switch child {
      case .text(let text): return text
      case .node(let id):
        guard let node = nodes[id] else { return "{missing \(id)}" }
        return "<\(node.tag)" + node.attributes.sorted { $0.key < $1.key }.map { " \($0.key)=\"\($0.value)\"" }.joined() + ">" + node.children.map(describe).joined() + "</\(node.tag)>"
      }
    }
  }

  // MARK: Fibers

  private struct Board: View {
    @State private var items = [1, 2, 3]
    @State private var next = 4
    @State private var title = "Title"
    @State private var flag = false
    @State private var extra = false
    @State private var name = "Ada"
    var body: some View {
      VStack {
        Text(title).opacity(flag ? 0.5 : 1)
        HStack {
          Button("add") { items.append(next); next += 1 }
          Button("remove") { if !items.isEmpty { items.removeFirst() } }
          Button("rotate") { if !items.isEmpty { items.append(items.removeFirst()) } }
          Button("title") { title = title == "Title" ? "Other" : "Title" }
          Button("flag") { flag.toggle() }
          Button("extra") { extra.toggle() }
          Button("name") { name = name == "Ada" ? "Grace" : "Ada" }
        }
        TextField("Name", text: $name)
        ForEach(items, id: \.self) { item in Text("item \(item)").padding(flag ? 4 : 0) }
        ForEach(items, id: \.self) { item in HStack { Text("a \(item)"); Text("b"); Text(flag ? "on" : "off") }.padding() }
        if extra { VStack { Text("extra"); Text("more") } }
      }
    }
  }

  private func buttons(in fiber: Fiber) -> [String: Fiber] {
    var found: [String: Fiber] = [:]
    var stack = [fiber]
    while let current = stack.popLast() {
      if current.renderNode.attributes["data-control-kind"] == "button" {
        var nodes = [current.renderNode], label = ""
        while let next = nodes.popLast() { if next.kind == .text, let text = next.text { label = text; break }; nodes.append(contentsOf: next.children) }
        found[label] = current
      }
      stack.append(contentsOf: current.children)
    }
    return found
  }

  /// A snapshot of the fiber tree as `BrowserApp` takes it, reduced to what the encoder reads: a copy of every fiber's node
  /// with its id, and a placeholder for the elements the host holds that did not change.
  private final class Snapshot {
    var written: [(fiber: Fiber, copy: _RenderNode, inHostContent: Bool)] = []
    var kept: [(fiber: Fiber, node: _RenderNode)] = []

    @MainActor
    func take(_ fiber: Fiber, root: Fiber, acked: UInt64) -> _RenderNode {
      let node = fiber.renderNode
      let id = "\(fiber.structuralID.index):\(fiber.structuralID.generation):\(node.descriptor ?? "")"
      if fiber !== root, BinaryHeldState.holds(fiber, acked: acked), !fiber.isVolatile, !fiber.publishedHostOwned, case .element(let tag) = node.kind {
        let keep = _RenderNode.element(StaticHTMLFiberRenderer.keepTag)
        keep.attributes["data-embedded-node-id"] = id
        keep.attributes["data-keep-tag"] = tag
        kept.append((fiber, keep))
        return keep
      }
      let copy = _RenderNode(kind: node.kind, text: node.text)
      copy.attributes = node.attributes
      copy.styles = node.styles
      copy.classes = node.classes
      copy.events = node.events
      copy.attributes.removeValue(forKey: "data-layout-schema")
      copy.attributes["data-embedded-node-id"] = id
      copy.children = fiber.children.map { take($0, root: root, acked: acked) }
      written.append((fiber, copy, false))
      return copy
    }
  }

  @Test
  func aPageThatReadsOnlyTheNewestPublicationAndAcknowledgesLateEndsInTheTreeSwiftHas() throws {
    for seed in 1...12 as ClosedRange<UInt64> {
      var random = SeededGenerator(seed: seed)
      let tree = FiberTree(Board(), deferLazyCollections: false, startLifecycle: false)
      defer { tree._dispose() }
      _ = tree.renderNode
      let page = Page()
      var acked: UInt64 = 0
      var latest: (bytes: [UInt8], covered: UInt64)?
      // The acknowledgements on their way back: the step they reach Swift at, and the epoch they carry.
      var acknowledgements: [(arrives: Int, epoch: UInt64)] = []
      var inFull = 0, incremental = 0, shapeInstances = 0
      var rootRecord = BinaryNodeRecord()
      let table = BinaryShapeTable(instancesBeforeDefinition: 2)
      func publish() throws {
        _ = tree.renderNode
        let holds = BinaryHeldState.holdsTree(rootRecord, acked: acked)
        let effective: UInt64 = holds ? acked : 0
        let snapshot = Snapshot()
        let copy = snapshot.take(tree.root, root: tree.root, acked: effective)
        let covered = tree._advanceEpoch()
        let encoder = BinaryFiberEncoder(maxElementDepth: 510, acked: effective, covered: covered, rootRecord: rootRecord, shapes: table, lookup: { node in
          MainActor.assumeIsolated {
            for entry in snapshot.written where entry.copy === node { return BinaryHeldState.record(of: entry.fiber) }
            for entry in snapshot.kept where entry.node === node { return BinaryHeldState.record(of: entry.fiber) }
            return nil
          }
        })
        let output = try #require(encoder.encode(copy))
        shapeInstances += output.shapeInstances
        BinaryHeldState.published(output, visited: snapshot.written, kept: snapshot.kept, covered: covered)
        rootRecord = output.rootRecord
        if holds { incremental += 1 } else { inFull += 1 }
        latest = (output.bytes, covered)
      }
      func read(step: Int) throws {
        guard let published = latest else { return }
        latest = nil
        page.apply(published.bytes)
        #expect(page.failed == nil, "seed \(seed), step \(step): \(page.failed ?? "")")
        // What the page ends with is what a page that received the whole tree would have.
        let whole = Snapshot().take(tree.root, root: tree.root, acked: 0)
        let reference = Page()
        let encoder = BinaryFiberEncoder(maxElementDepth: 510, acked: 0, covered: 1, rootRecord: BinaryNodeRecord(), lookup: { _ in nil })
        reference.apply(try #require(encoder.encode(whole)).bytes)
        #expect(page.description() == reference.description(), "seed \(seed), step \(step)")
        acknowledgements.append((step + Int(random.next() % 3), published.covered))
      }
      try publish()
      let labels = ["add", "remove", "rotate", "title", "flag", "extra", "name"]
      for step in 0..<60 {
        let label = labels[Int(random.next() % UInt64(labels.count))]
        // Now and then the page asks for a publication in full: it forgets what it holds, and so does the table.
        if random.next() % 13 == 0 { table.reset(); acked = 0; rootRecord = BinaryNodeRecord(); acknowledgements.removeAll() }
        if let button = buttons(in: tree.root)[label] { tree.dispatch(event: "click", at: button.identity) }
        try publish()
        // The page reads when it likes: a publication it does not read before the next one is dropped.
        if random.next() % 3 != 0 { try read(step: step) }
        for acknowledgement in acknowledgements where acknowledgement.arrives <= step { acked = max(acked, acknowledgement.epoch) }
        acknowledgements.removeAll { $0.arrives <= step }
        if page.failed != nil { break }
      }
      try read(step: 99)
      #expect(incremental > 10, "seed \(seed) made \(incremental) incremental publications and \(inFull) in full")
      #expect(shapeInstances > 10, "seed \(seed) built \(shapeInstances) subtrees as shapes")
    }
  }

  // MARK: Fixtures for the page's tests

  /// An element of a placement fixture, with the id a fiber would give it.
  private static func node(_ tag: String, _ id: String? = nil, _ children: [_RenderNode] = []) -> _RenderNode {
    C.element(tag, id.map { ["data-embedded-node-id": $0] } ?? [:], children)
  }

  /// A decoded tree's description as markup: without its namespace prefixes and the end tags of void elements.
  private static func markup(of description: String) -> String {
    var markup = description.replacingOccurrences(of: "svg:", with: "").replacingOccurrences(of: "math:", with: "")
    for tag in ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"] {
      markup = markup.replacingOccurrences(of: "</\(tag)>", with: "")
    }
    return markup
  }

  /// The trees `Tools/test-binary-publication-browser.mjs` builds from the stream and compares with what the parser makes of
  /// the markup beside it.
  private static var fixtures: [(name: String, depth: Int?, make: @MainActor () -> _RenderNode)] {
    var list: [(String, Int?, @MainActor () -> _RenderNode)] = [
      ("attributes", nil, {
        C.element("div", ["data-embedded-node-id": "1:1:root", "title": "a \"quoted\" & <b>", "data-empty": "", "tabindex": "0"], classes: ["one", "two"],
                  styles: ["color": "red", "--len0": "4px"], events: ["click": "tap"], [
          C.text("Hello & goodbye <world>", classes: ["t"]), .text("plain"), .text(" plain too"),
          C.element("button", ["type": "button", "aria-label": "Open"], classes: ["button"], [.text("Open")]),
        ])
      }),
      ("texts", nil, {
        C.element("div", [:], [
          .text("a"), .text("b"), C.element("span", [:], [.text("tab\there"), .text("\r\n"), .text("line\rend")]),
          C.element("textarea", ["data-embedded-node-id": "t1"], [.text("\nfirst line dropped\nsecond")]),
          C.element("textarea", ["data-embedded-node-id": "t2"], [.text("\n\ntwo breaks")]),
          C.element("option", ["value": "1"], [.text("One & <Two>")]),
          C.element("pre", [:], [.text("\nkept? no: the parser drops one leading line feed")]),
          C.element("title", [:], [.text("&amp; stays \"&\"")]),
          C.element("style", [:], [.text("a > b { content: \"&\"; }")]),
          C.element("script", [:], [.text("alert(1)")]),
          C.element("noscript", [:], [.text("<p>&</p>")]),
          C.element("template", [:], [C.element("p", [:], [.text("inside the template")])]),
          .text("é 日本語 😀"), C.element("i"), .text("after"),
        ])
      }),
      ("foreign", nil, {
        C.element("div", [:], [
          C.element("svg", ["viewBox": "0 0 24 24", "xmlns": "http://www.w3.org/2000/svg", "preserveAspectRatio": "none", "xlink:href": "#a", "class": "icon"], [
            C.element("defs", [:], [
              C.element("linearGradient", ["id": "g", "gradientUnits": "userSpaceOnUse", "gradientTransform": "rotate(5)"], [C.element("stop", ["offset": "0", "stop-color": "red"])]),
              C.element("clipPath", ["id": "c", "clipPathUnits": "objectBoundingBox"], [C.element("rect", ["width": "1", "height": "1"])]),
            ]),
            C.element("path", ["d": "M0 0L1 1", "stroke-linecap": "round", "fill": "url(#g)"]),
            C.element("text", ["x": "1"], [.text("a & b"), C.element("tspan", [:], [.text("<t>")])]),
            C.element("foreignObject", ["width": "10", "height": "10"], [C.element("div", ["class": "html"], [C.element("span", [:], [.text("html in svg")])])]),
            C.element("title", [:], [.text("svg title")]),
            C.element("desc", [:], [C.element("b", [:], [.text("desc html")])]),
            C.element("image", ["href": "x.png"]),
            C.element("style", [:], [.text("a{b:c}")]),
          ]),
          C.element("math", ["display": "block", "definitionURL": "u"], [C.element("mi", [:], [.text("x")]), C.element("mo", [:], [.text("+")]), C.element("annotation-xml", ["encoding": "text/html"], [C.element("div", [:], [.text("html in math")])])]),
          C.element("image", ["src": "a.png"]),
        ])
      }),
      ("void-and-controls", nil, {
        C.element("form", [:], [
          C.element("input", ["type": "text", "value": "v", "data-embedded-node-id": "i1"]), C.element("input", ["type": "checkbox", "checked": "", "data-embedded-node-id": "i2"]),
          C.element("br"), C.element("img", ["src": "x.png", "alt": "x", "loading": "lazy"]),
          C.element("select", ["data-embedded-node-id": "s1"], [C.element("option", ["value": "a", "selected": ""], [.text("A")]), C.element("option", ["value": "b"], [.text("B")])]),
          C.element("details", ["open": ""], [C.element("summary", [:], [.text("s")]), .text("body")]),
          C.element("video", ["src": "v.mp4", "controls": ""]), C.element("iframe", ["src": "about:blank"]),
          C.element("table", [:], [C.element("thead", [:], [C.element("tr", [:], [C.element("th", [:], [.text("h")])])]), C.element("tbody", [:], [C.element("tr", [:], [C.element("td", [:], [.text("d")])])])]),
          C.element("ul", [:], [C.element("li", [:], [.text("one")]), C.element("li", [:], [.text("two")])]),
        ])
      }),
      ("handles", nil, {
        C.element("section", ["data-embedded-node-id": "1:1:s"], [
          C.text(String(repeating: "long text ", count: 30), ["data-embedded-node-id": "2:3:t"], classes: ["t"]),
          C.element("div", ["data-embedded-node-id": "3:1:d"], [C.element("textarea", ["data-embedded-node-id": "4:7:ta"], [.text(String(repeating: "x", count: 200))])]),
          C.element("span", ["data-embedded-node-id": "5:1:small"], [.text("small")]),
        ])
      }),
      // Rows the table defines a shape for, with values that differ, an svg inside and a text whose first line feed the parser keeps.
      ("shapes", nil, {
        C.element("ul", ["data-embedded-node-id": "1:1:list"], (0..<7).map { index in
          C.element("li", ["data-embedded-node-id": "\(10 + index):2:row", "class": index % 2 == 0 ? "even" : "odd", "data-n": "\(index)"], [
            C.element("span", ["data-embedded-node-id": "\(30 + index):1:", "title": "t\(index)"], [.text("row \(index) & <b>")]),
            C.element("svg", ["data-embedded-node-id": "\(50 + index):1:", "viewBox": "0 0 24 24"], [C.element("path", ["data-embedded-node-id": "\(70 + index):1:", "d": "M0 \(index)", "xlink:href": "#a\(index)"])]),
            C.element("button", ["data-embedded-node-id": "\(90 + index):1:", "type": "button"], [.text(index == 3 ? "go\r\nnow" : "go")]),
          ])
        })
      }),
      ("deep-limit", 12, { C.chain(40) }),
      ("deep-limit-foreign", 4, { C.element("div", [:], [C.element("div", [:], [C.element("div", [:], [C.element("svg", [:], [C.element("g", [:], [C.element("path")])])])])]) }),
      ("fragments", nil, { C.fragment([.text("a"), C.fragment([.empty(), C.element("div", [:], [C.fragment([.text("b"), C.element("i")]), .empty()])]), .text("c")]) }),
    ]
    list += C.views.map { tree in (tree.name, nil, tree.make) }
    // What the parser would restructure, written as trees it keeps (`Placement` in BinaryEncoder.swift).
    let placed: [(String, Int?, @MainActor () -> _RenderNode)] = [
      ("placed-nesting", nil, {
        Self.node("div", "1:1:", [
          Self.node("form", "2:1:", [Self.node("div", nil, [Self.node("form", "3:1:", [.text("inner form")])])]),
          Self.node("a", "4:1:", [Self.node("span", nil, [Self.node("a", "5:1:", [.text("inner link")])])]),
          Self.node("p", "6:1:", [Self.node("span", nil, [Self.node("div", "7:1:", [.text("block in a paragraph")])])]),
          Self.node("ul", nil, [Self.node("li", "8:1:", [Self.node("span", nil, [Self.node("li", "9:1:", [.text("item in an item")])])])]),
          Self.node("h1", nil, [Self.node("h2", "10:1:", [.text("heading in a heading")])]),
          Self.node("nobr", nil, [Self.node("b", nil, [Self.node("nobr", nil, [.text("x")])])]),
          Self.node("div", nil, [Self.node("body", "11:1:")]),
        ])
      }),
      ("placed-select", nil, {
        Self.node("select", "1:1:", [
          Self.node("option", "2:1:", [Self.node("span", nil, [.text("Styled ")]), .text("label"), Self.node("option", nil, [.text(" inner")])]),
          Self.node("div", "3:1:", [.text("not an option")]),
          Self.node("optgroup", nil, [Self.node("span", nil, [.text("in a group")]), Self.node("option", nil, [.text("grouped")])]),
        ])
      }),
      ("placed-tables", nil, {
        Self.node("div", "1:1:", [
          Self.node("td", "2:1:", [.text("cell outside a row")]),
          Self.node("tr", "3:1:", [Self.node("td", nil, [.text("row outside a table")])]),
          Self.node("table", "4:1:", [
            Self.node("tr", "5:1:", [Self.node("td", nil, [.text("row in a table")])]),
            Self.node("div", "6:1:", [.text("block in a table")]),
            Self.node("col"),
            Self.node("tbody", nil, [Self.node("td", "7:1:", [.text("cell in a section")]), .text("text in a section"), Self.node("tr", nil, [Self.node("div", nil, [.text("block in a row")]), Self.node("table", nil, [Self.node("tbody", nil, [Self.node("tr", nil, [Self.node("td", nil, [.text("table in a row")])])])])])]),
          ]),
        ])
      }),
      ("placed-foreign", nil, {
        Self.node("div", "1:1:", [
          Self.node("svg", "2:1:", [Self.node("g", nil, [Self.node("div", "3:1:", [Self.node("circle")])]), C.text("label", classes: ["t"])]),
          Self.node("math", "4:1:", [Self.node("p", "5:1:", [Self.node("mi", nil, [.text("x")])])]),
        ])
      }),
    ]
    list += placed
    return list
  }

  /// The repository's fixture folder, on the test host's disk (`HostFiles`), where the page tests read them.
  private static var fixtureDirectory: String {
    HostFiles.parent(HostFiles.directory()) + "/Fixtures/BinaryPublication"
  }

  @Test
  func theFixturesOfThePageTestsAreCurrent() throws {
    let update = HostFiles.environment("SWIFTUIWEB_UPDATE_BINARY_FIXTURES") == "1"
    var stale: [String] = []
    for fixture in Self.fixtures {
      let result = publish(fixture.make(), depth: fixture.depth, shapes: fixture.name.hasPrefix("shapes") ? BinaryShapeTable() : nil)
      guard let stream = result.stream else { stale.append("\(fixture.name) was declined"); continue }
      // A tree written as another the parser keeps (`placed-...`) is compared with the parser's DOM of that other tree's markup:
      // the page must build what the parser would build of it.
      let markup = fixture.name.hasPrefix("placed-") ? Self.markup(of: DecodedPublication(stream).description) : result.html
      for (name, bytes) in [("\(fixture.name).bin", Array(stream)), ("\(fixture.name).html", Array(markup.utf8))] {
        let path = Self.fixtureDirectory + "/" + name
        if update { HostFiles.write(bytes, to: path) } else if HostFiles.read(path) != bytes { stale.append(name) }
      }
    }
    #expect(stale.isEmpty, "stale fixtures (SWIFTUIWEB_UPDATE_BINARY_FIXTURES=1 rewrites them): \(stale)")
  }
}

/// A small deterministic generator, so that a failing seed can be run again.
private struct SeededGenerator {
  var state: UInt64
  init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
  mutating func next() -> UInt64 {
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state
  }
}

/// The view-transition header flag (`BinaryFiberEncoder.transitionFlag`): set only by a publication that names an element for a
/// view transition, so every other publication is applied exactly as before.
@Suite
@MainActor
struct BinaryViewTransitionFlagTests {
  private struct Named: View {
    @Namespace private var namespace
    var body: some View { Text("Hero").matchedTransitionSource(id: "hero", in: namespace) }
  }

  @Test
  func aPublicationNamingAnElementSetsTheTransitionFlag() throws {
    let stream = try #require(publish(FiberTree(Named()).renderNode).stream)
    #expect(stream[6] & 2 != 0)
  }

  @Test
  func aPublicationWithoutANamedElementLeavesTheFlagClear() throws {
    let stream = try #require(publish(FiberTree(Text("Plain")).renderNode).stream)
    #expect(stream[6] & 2 == 0)
  }
}
