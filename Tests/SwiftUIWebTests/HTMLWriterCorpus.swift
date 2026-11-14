@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebHTML
@testable import SwiftUIWeb

/// The trees and option sets `HTMLWriterReferenceTests` serializes: hand-built edge cases, seeded random trees, large and
/// deep generated trees, and views rendered by the framework. Everything is deterministic.
struct HTMLWriterCorpus {
  struct Tree {
    let name: String
    let make: @MainActor () -> _RenderNode
  }

  /// One combination of the renderer's options.
  struct Options {
    let name: String
    var depth: Int?
  }

  static let options: [Options] = [
    Options(name: "plain"),
    Options(name: "plain-depth4", depth: 4),
    Options(name: "plain-depth0", depth: 0),
  ]

  // MARK: Building

  @MainActor static func element(
    _ tag: String,
    _ attributes: KeyValuePairs<String, String> = [:],
    classes: [String] = [],
    styles: KeyValuePairs<String, String> = [:],
    events: KeyValuePairs<String, String> = [:],
    _ children: [_RenderNode] = []
  ) -> _RenderNode {
    let node = _RenderNode.element(tag)
    for (key, value) in attributes { node.attributes[key] = value }
    node.classes = classes
    for (key, value) in styles { node.styles[key] = value }
    for (key, name) in events { node.events[key] = _EventHandler(name: name, action: {}) }
    node.children = children
    return node
  }

  @MainActor static func text(_ text: String, _ attributes: KeyValuePairs<String, String> = [:], classes: [String] = []) -> _RenderNode {
    let node = _RenderNode.text(text)
    for (key, value) in attributes { node.attributes[key] = value }
    node.classes = classes
    return node
  }

  @MainActor static func fragment(_ children: [_RenderNode]) -> _RenderNode {
    let node = _RenderNode.fragment()
    node.children = children
    return node
  }

  /// A chain of `levels` elements, each the only child of the one above, ending in a text leaf.
  @MainActor static func chain(_ levels: Int, tag: String = "div", leaf: String = "leaf", ids: Bool = true) -> _RenderNode {
    var node: _RenderNode = .text(leaf)
    var level = levels
    while level > 0 {
      level -= 1
      let parent = _RenderNode.element(tag)
      if ids { parent.attributes["data-embedded-node-id"] = "c:\(level)" }
      parent.children = [node]
      node = parent
    }
    return node
  }

  // MARK: Hand-built trees

  static let allASCII: String = String(decoding: (0...127).map { UInt8($0) }, as: UTF8.self)
  static let special = "&<>\"'"
  static let unicodeSamples = [
    "caf\u{E9} cafe\u{301}", "ção ñ ü", "日本語のテキスト", "한국어", "Привет мир", "שלום עולם", "مرحبا", "😀 👩‍👩‍👧‍👦 🏳️‍🌈 🇧🇷",
    "\u{FEFF}bom\u{200B}zwsp\u{200D}zwj", "\u{10FFFF}\u{FFFF}\u{FFFE}\u{1F600}", "a\u{0}b\u{0}\u{0}c", "tab\there\nnewline\r\n",
    "\u{7F}\u{80}\u{9F}\u{A0}\u{2028}\u{2029}",
  ]

  static var handBuilt: [Tree] {
    [
      Tree(name: "empty") { .empty() },
      Tree(name: "text-plain") { .text("hello") },
      Tree(name: "text-nil") { _RenderNode(kind: .text, text: nil) },
      Tree(name: "text-styled") { text("hi", classes: ["t"]) },
      Tree(name: "text-attribute-only") { text("hi", ["title": "t&t"]) },
      Tree(name: "text-events-only") {
        let node = text("hi")
        node.events["appear"] = _EventHandler(name: "appear", action: {})
        node.events["click"] = _EventHandler(name: "c", action: {})
        return node
      },
      Tree(name: "text-lifecycle-events-only") {
        let node = text("hi")
        node.events["appear"] = _EventHandler(name: "a", action: {})
        node.events["task"] = _EventHandler(name: "t", action: {})
        return node
      },
      Tree(name: "text-styles-only") {
        let node = text("hi")
        node.styles["color"] = "red"
        return node
      },
      Tree(name: "text-in-element-long") {
        element("p", ["id": "p"], [text(String(repeating: "lorem ipsum dolor sit amet ", count: 400)), text("short"), text("")])
      },
      Tree(name: "fragment-empty") { fragment([]) },
      Tree(name: "fragment-nested") {
        fragment([.text("a"), fragment([.empty(), .text("b"), fragment([text("c", classes: ["x"])])]), .empty()])
      },
      Tree(name: "fragment-in-element") {
        element("div", ["id": "d"], [fragment([.text("a"), element("span", [:], [.text("b")])]), fragment([]), .empty()])
      },
      Tree(name: "element-bare") { element("div") },
      Tree(name: "element-empties") { element("div", [:], [.empty(), .empty(), fragment([.empty()])]) },
      Tree(name: "escape-ascii-text") {
        element("div", [:], [.text(allASCII), .text(special), .text(String(repeating: special, count: 50)), .text("a&b"), .text("&"), .text("'")])
      },
      Tree(name: "escape-ascii-attributes") {
        element("div", ["title": allASCII, "data-a": special, "data-b": String(repeating: special, count: 40), "data-c": "", "data-d": "&"],
                classes: [special, allASCII, "", "plain"], styles: [special: special, "color": allASCII, "": ""])
      },
      Tree(name: "escape-unicode") {
        element("div", [:], unicodeSamples.map { text($0) } + [element("a", ["title": unicodeSamples.joined(separator: "|"), "data-é": "ü"], classes: unicodeSamples)])
      },
      Tree(name: "escape-long") {
        let long = (0..<20_000).map { index -> String in
          switch index % 7 { case 0: "&"; case 1: "<"; case 2: ">"; case 3: "\""; case 4: "'"; case 5: "é"; default: "text" }
        }.joined()
        return element("div", ["title": long], classes: [long], styles: ["background": long], [.text(long), .text(String(repeating: "x", count: 100_000))])
      },
      Tree(name: "weird-attribute-names") {
        element("div", ["": "empty-key", "a\"b": "1", "a<b": "2", "a b": "3", "a=b": "4", "é": "5", "e\u{301}": "6", "😀": "7", "\u{0}": "8", "-": "9"])
      },
      Tree(name: "weird-tags") {
        element("DIV", [:], [element("my-element", [:], [.text("x")]), element("", [:], [.text("empty tag")]), element("a b", [:], [.text("space")]),
                              element("tèst", [:], [.text("accent")]), element("x\"y", [:], [.text("quote")]), element("😀", [:], [.text("emoji")]),
                              element("a-very-long-tag-name-that-does-not-fit-a-small-string", ["id": "long"], [.text("long")])])
      },
      Tree(name: "attribute-order") {
        element("div", [
          "title": "t", "data-z": "1", "data-a": "2", "Data-A": "3", "data-ab": "4", "data-a-b": "5", "data_a": "6", "data-1": "7", "data-10": "8", "data-2": "9",
          "aria-label": "l", "ARIA-HIDDEN": "true", "z": "z", "a": "a", "A": "A", "id": "i", "data-embedded-node-id": "7:1:x", "data-layout-kind": "text",
          "href": "h", "hidden": "", "tabindex": "0", "role": "button", "draggable": "true", "data-fiber-event-click": "attr-wins-or-loses",
        ], classes: ["k1", "k2"], styles: ["z-index": "1", "color": "red", "--custom": "1", "Color": "b", "background": "x", "-webkit-x": "y"],
        events: ["click": "c1", "pointerdown": "p", "keydown.enter": "k", "appear": "a", "disappear": "d", "task": "t", "geometry": "g", "geometryChange": "gc",
                 "openURL": "o", "presentation-dismiss": "pd", "web-navigation": "wn", "web-external-link": "we", "a": "ea", "z": "ez", "data-q": "dq"])
      },
      Tree(name: "attribute-order-unicode") {
        element("div", ["é": "1", "e\u{301}": "2", "z": "3", "f": "4", "ä": "5", "Z": "6", "😀": "7", "\u{FF5E}": "8", "\u{1F600}": "9", "a\u{301}": "10", "á": "11", "e": "12", "ez": "13"],
                styles: ["é": "1", "e\u{301}": "2", "z": "3", "😀": "7", "\u{FF5E}": "8", "á": "9"])
      },
      Tree(name: "class-variants") {
        element("section", [:], [
          element("div", ["class": "only-attribute"]),
          element("div", [:], classes: ["only", "list"]),
          element("div", ["class": "prefix"], classes: ["a", "b"]),
          element("div", ["class": ""], classes: ["a"]),
          element("div", ["class": ""]),
          element("div", ["class": "has&<>"], classes: ["x'y"]),
          element("div", ["data-layout-kind": "vstack"]),
          element("div", ["data-layout-kind": "vstack", "class": "c"]),
          element("div", ["data-layout-kind": "vstack", "class": ""]),
          element("div", ["data-layout-kind": "vstack"], classes: ["k"]),
          element("div", ["data-layout-kind": "vstack", "class": "c"], classes: ["k"]),
          text("t", ["class": "attr"], classes: ["list"]),
          text("t", ["class": "attr"]),
          text("t", [:], classes: ["list"]),
        ])
      },
      Tree(name: "style-variants") {
        element("section", [:], [
          element("div", ["style": "only: attribute;"]),
          element("div", [:], styles: ["color": "red"]),
          element("div", ["style": "prefix: 1;"], styles: ["color": "red", "background": "blue"]),
          element("div", ["style": ""], styles: ["color": "red"]),
          element("div", ["style": ""]),
          element("div", [:], styles: ["color": ""]),
          element("div", [:], styles: ["z": "1", "a": "2", "M": "3", "m": "4", "--x": "5", "-y": "6", "0": "7", "é": "8", "ab": "9", "a-b": "10", "a_b": "11"]),
          element("div", ["style": "&<>"], styles: ["a'b": "c\"d"]),
          text("t", ["style": "attr: 1;"]),
        ])
      },
      Tree(name: "events") {
        element("section", [:], [
          element("button", [:], events: ["click": "tap"]),
          element("button", [:], events: ["click": "x&y\"z"]),
          element("div", [:], events: ["appear": "a"]),
          element("div", [:], events: ["appear": "a", "disappear": "d", "task": "t", "geometry": "g", "geometryChange": "gc", "openURL": "o", "presentation-dismiss": "p", "web-navigation": "n", "web-external-link": "e"]),
          element("div", ["data-fiber-event-click": "attribute"], events: ["click": "event"]),
          element("div", ["data-fiber-event-click": "attribute"], events: ["tap": "other"]),
          element("div", [:], events: ["Click": "upper", "click": "lower", "click ": "space", "é": "unicode", "a\"b": "quote"]),
          element("div", [:], events: ["a-very-long-event-name-that-exceeds-a-small-string": "long-handler-name-that-exceeds-a-small-string-too"]),
          element("div", [:], events: ["": "empty-name"]),
        ])
      },
      Tree(name: "hit-transparent") {
        let layouts = ["zstack", "vstack", "hstack", "grid", "gridrow", "spacer", "frame", "flexible", "inset", "padding", "container-relative", "geometry",
                       "intrinsic", "position", "offset", "fixed", "overlay", "background", "aspect", "text", "scroll", "button", ""]
        var children: [_RenderNode] = layouts.map { element("div", ["data-layout-kind": $0]) }
        for name in ["data-content-shape", "data-background-style", "tabindex", "role", "contenteditable", "data-press-tracking", "draggable"] {
          children.append(element("div", ["data-layout-kind": "vstack", name: "x"]))
        }
        children.append(element("div", ["data-layout-kind": "vstack"], events: ["click": "c"]))
        children.append(element("div", ["data-layout-kind": "vstack"], events: ["appear": "a", "task": "t"]))
        for style in ["background-color", "border-radius", "box-shadow", "outline-color", "backdrop-filter", "filter", "mask-image", "color", "padding", "backgroundx", "filtered", "x-filter"] {
          children.append(element("div", ["data-layout-kind": "hstack"], styles: [style: "v"]))
        }
        children.append(element("div", ["data-layout-kind": "vstack"], classes: ["scroll-view"]))
        children.append(element("div", ["data-layout-kind": "vstack"], classes: ["tab-view", "x"]))
        children.append(element("div", ["data-layout-kind": "vstack"], classes: ["other"]))
        children.append(element("div", ["data-layout-kind": "vstack"], [.text("child")]))
        children.append(text("t", ["data-layout-kind": "vstack"]))
        return element("div", [:], children)
      },
      Tree(name: "void-tags") {
        let tags = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
        var children: [_RenderNode] = []
        for tag in tags {
          children.append(element(tag, ["id": tag, "data-embedded-node-id": "v:\(tag)"]))
          children.append(element(tag.uppercased(), ["id": tag]))
          children.append(element(tag, ["id": tag], [.text("ignored child"), element("span", [:], [.text("ignored too")])]))
        }
        children += [element("Br"), element("IMG"), element("Input", ["value": "x"]), element("trac\u{212A}"), element("lin\u{212A}"), element("TRAC\u{212A}"), element("img\u{0}"),
                     element("im"), element("imgs"), element("sourc"), element("source "), element("wbr\u{0}")]
        return element("div", [:], children)
      },
      Tree(name: "void-root") { element("img", ["src": "a&b"], [.text("child")]) },
      Tree(name: "host-owned") {
        let tags = ["input", "textarea", "select", "option", "details", "dialog", "video", "audio", "canvas", "iframe", "object", "embed"]
        var children: [_RenderNode] = []
        for tag in tags {
          children.append(element(tag, ["data-embedded-node-id": "h:\(tag)"], [.text("inside \(tag)")]))
          children.append(element(tag.uppercased(), ["data-embedded-node-id": "h:\(tag.uppercased())"], [.text("inside")]))
        }
        for name in ["contenteditable", "data-keep-secure-id", "data-keep-lazy-index", "data-timeline-view", "data-web-mount-flag", "data-mesh-gradient", "data-tab-panel", "popover"] {
          children.append(element("div", [name: "1", "data-embedded-node-id": "a:\(name)"], [element("span", [:], [.text("under \(name)")])]))
        }
        children.append(element("button", ["role": "tab", "data-embedded-node-id": "role-tab"], [.text("tab")]))
        children.append(element("button", ["role": "button", "data-embedded-node-id": "role-button"], [.text("button")]))
        children.append(element("button", ["role": "Tab", "data-embedded-node-id": "role-Tab"], [.text("Tab")]))
        children.append(element("div", ["data-embedded-node-id": "tabview"], classes: ["tab-view"], [.text("tab view")]))
        children.append(element("div", ["data-embedded-node-id": "tabviewx"], classes: ["tab-views", "x-tab-view"], [.text("not a tab view")]))
        children.append(element("div", ["data-embedded-node-id": "calm"], [.text("calm")]))
        children.append(element("details", [:], [.text("no id")]))
        return element("main", ["data-embedded-node-id": "root"], children)
      },
      Tree(name: "keep-placeholders") {
        element("div", ["data-embedded-node-id": "root"], [
          element("keep", ["data-embedded-node-id": "1", "data-keep-hash": "0123456789abcdef"]),
          element("keep", ["data-keep-hash": "ABCDEF0123456789"]),
          element("keep", ["data-keep-hash": "~~~~~~~~~~~~~~~~"]),
          element("keep", ["data-keep-hash": "xyz"]),
          element("keep", ["data-keep-hash": "00000000000000000000ffff"]),
          element("keep", ["data-keep-hash": ""]),
          element("keep", ["data-embedded-node-id": "no-hash"]),
          element("keep", ["data-keep-hash": "fedcba9876543210", "class": "c"], classes: ["k"], styles: ["color": "red"], [.text("ignored child")]),
          element("Keep", ["data-keep-hash": "0123456789abcdef"], [.text("not the keep tag")]),
          element("keeper", ["data-keep-hash": "0123456789abcdef"]),
          element("section", ["data-embedded-node-id": "2"], [element("keep", ["data-keep-hash": "1111111111111111"]), .text("sibling")]),
        ])
      },
      Tree(name: "sibling-order-hash") {
        // The same children in two orders and with a repeat: the combined hash depends on order.
        element("div", [:], [
          element("ul", ["data-embedded-node-id": "ab"], [element("li", [:], [.text("a")]), element("li", [:], [.text("b")])]),
          element("ul", ["data-embedded-node-id": "ba"], [element("li", [:], [.text("b")]), element("li", [:], [.text("a")])]),
          element("ul", ["data-embedded-node-id": "aa"], [element("li", [:], [.text("a")]), element("li", [:], [.text("a")])]),
          element("ul", ["data-embedded-node-id": "empties"], [.empty(), .empty(), .text("")]),
          element("ul", ["data-embedded-node-id": "frags"], [fragment([.text("a")]), fragment([.text("b")])]),
        ])
      },
      Tree(name: "deep-20") { chain(20) },
      Tree(name: "deep-300") { chain(300) },
      Tree(name: "deep-600") { chain(600) },
      Tree(name: "deep-2000") { chain(2000, ids: false) },
      Tree(name: "deep-mixed") {
        var node: _RenderNode = .text("bottom")
        for level in 0..<700 {
          let parent = element(level % 5 == 0 ? "section" : "div", ["data-embedded-node-id": "m:\(level)"])
          var siblings: [_RenderNode] = [node]
          if level % 3 == 0 { siblings.append(element("br")) }
          if level % 7 == 0 { siblings.append(fragment([.text("f\(level)"), element("span", [:], [.text("s\(level)")])])) }
          if level % 11 == 0 { siblings.append(element("input", ["value": "v\(level)"])) }
          if level % 13 == 0 { siblings.append(.empty()) }
          if level % 17 == 0 { siblings.insert(.text("lead\(level)"), at: 0) }
          parent.children = siblings
          node = parent
        }
        return node
      },
      Tree(name: "deep-void-bottom") {
        let leaf = element("img", ["src": "x"], [.text("ignored")])
        var node: _RenderNode = leaf
        for level in 0..<20 { node = element("div", ["data-embedded-node-id": "dv:\(level)"], [node, .text("t\(level)")]) }
        return node
      },
      Tree(name: "wide-3000") {
        element("ul", ["data-embedded-node-id": "wide"], (0..<3000).map { element("li", ["data-embedded-node-id": "w:\($0)", "class": "row"], [.text("item \($0)")]) })
      },
    ]
  }

  // MARK: Generated trees

  struct Random {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
      return state
    }
    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
    mutating func pick<T>(_ values: [T]) -> T { values[below(values.count)] }
  }

  private static let randomTags = ["div", "span", "p", "section", "ul", "li", "button", "a", "img", "input", "br", "textarea", "select", "keep", "details", "h1", "label", "svg", "path", "IMG", "Div", "video"]
  private static let randomKeys = ["id", "title", "data-embedded-node-id", "data-layout-kind", "role", "href", "value", "data-a", "data-b", "aria-label", "tabindex", "hidden", "data-keep-hash", "popover", "contenteditable", "draggable", "data-tab-panel", "é", "z", "A"]
  private static let randomValues = ["", "x", "hello world", "a&b", "<tag>", "\"quoted\"", "it's", "café", "😀", "vstack", "hstack", "text", "tab", "0123456789abcdef", "1", "true", "a very long value that is certainly longer than fifteen bytes", "\u{0}", "7:1:node"]
  private static let randomClasses = ["row", "card", "tab-view", "scroll-view", "x&y", "plain", "a", "b", "é"]
  private static let randomStyles = ["color", "background-color", "padding", "z-index", "--var", "border-radius", "filter", "margin-top", "display"]
  private static let randomEvents = ["click", "appear", "disappear", "task", "geometry", "pointerdown", "keydown", "web-navigation", "input"]

  @MainActor static func randomTree(seed: UInt64, nodes: Int) -> _RenderNode {
    var random = Random(seed: seed)
    var budget = nodes
    func make(depth: Int) -> _RenderNode {
      budget -= 1
      let roll = random.below(100)
      if roll < 20 || depth > 9 || budget <= 0 {
        if random.chance(10) { return .empty() }
        let node = _RenderNode.text(random.pick(randomValues) + (random.chance(30) ? random.pick(unicodeSamples) : ""))
        if random.chance(15) { node.classes = [random.pick(randomClasses)] }
        if random.chance(5) { node.attributes[random.pick(randomKeys)] = random.pick(randomValues) }
        if random.chance(5) { node.styles[random.pick(randomStyles)] = random.pick(randomValues) }
        if random.chance(4) { node.events[random.pick(randomEvents)] = _EventHandler(name: "h", action: {}) }
        return node
      }
      if roll < 26 {
        let node = _RenderNode.fragment()
        node.children = (0..<random.below(4)).map { _ in make(depth: depth + 1) }
        return node
      }
      let node = _RenderNode.element(random.pick(randomTags))
      for _ in 0..<random.below(6) { node.attributes[random.pick(randomKeys)] = random.pick(randomValues) }
      if random.chance(40) { node.attributes["data-embedded-node-id"] = "r:\(random.below(1000))" }
      if random.chance(30) { node.classes = (0..<random.below(4)).map { _ in random.pick(randomClasses) } }
      if random.chance(30) { for _ in 0..<random.below(4) { node.styles[random.pick(randomStyles)] = random.pick(randomValues) } }
      if random.chance(25) { for _ in 0..<random.below(3) { node.events[random.pick(randomEvents)] = _EventHandler(name: random.pick(randomValues), action: {}) } }
      var children: [_RenderNode] = []
      let count = random.chance(20) ? 0 : 1 + random.below(depth < 3 ? 6 : 3)
      for _ in 0..<count where budget > 0 { children.append(make(depth: depth + 1)) }
      node.children = children
      return node
    }
    let root = _RenderNode.element("div")
    root.attributes["data-embedded-node-id"] = "root"
    var children: [_RenderNode] = []
    while budget > 0 { children.append(make(depth: 1)) }
    root.children = children
    return root
  }

  /// About 1,400 elements the way a large app's works list writes them: rows of layout containers, text, a badge,
  /// an image and a button.
  @MainActor static func worksList(rows: Int) -> _RenderNode {
    let list = element("div", ["data-embedded-node-id": "1:1:list", "data-layout-kind": "vstack"], classes: ["scroll-view"], styles: ["display": "flex", "flex-direction": "column", "gap": "8px"])
    list.children = (0..<rows).map { index in
      element("div", ["data-embedded-node-id": "1:1:row-\(index)", "data-layout-kind": "hstack", "class": "work-row"], classes: index % 3 == 0 ? ["selected"] : [],
              styles: ["display": "flex", "padding": "8px 12px", "align-items": "center", "background-color": index % 2 == 0 ? "#fff" : "#f7f7f7"], [
        element("img", ["data-embedded-node-id": "1:1:cover-\(index)", "src": "https://example.com/covers/\(index).jpg?size=64&fit=cover", "alt": "Cover of work \(index)", "width": "48", "height": "48"],
                styles: ["border-radius": "6px", "object-fit": "cover"]),
        element("div", ["data-embedded-node-id": "1:1:text-\(index)", "data-layout-kind": "vstack"], styles: ["flex": "1", "min-width": "0"], [
          text("Work title number \(index) \"Quoted\" & more", classes: ["title"]),
          text("Author \(index % 40) · \(1990 + index % 35)", classes: ["subtitle"]),
        ]),
        element("span", ["data-embedded-node-id": "1:1:badge-\(index)", "role": "status"], classes: ["badge", index % 4 == 0 ? "badge-draft" : "badge-published"], [.text(index % 4 == 0 ? "Draft" : "Published")]),
        element("button", ["data-embedded-node-id": "1:1:open-\(index)", "type": "button", "aria-label": "Open work \(index)"], classes: ["button"], events: ["click": "open"], [.text("Open")]),
      ])
    }
    return list
  }

  static var generated: [Tree] {
    [
      Tree(name: "random-5") { randomTree(seed: 5, nodes: 5) },
      Tree(name: "random-40") { randomTree(seed: 40, nodes: 40) },
      Tree(name: "random-40b") { randomTree(seed: 41, nodes: 40) },
      Tree(name: "random-300") { randomTree(seed: 300, nodes: 300) },
      Tree(name: "random-2000") { randomTree(seed: 2000, nodes: 2000) },
      Tree(name: "random-20000") { randomTree(seed: 20_000, nodes: 20_000) },
      Tree(name: "works-list-small") { worksList(rows: 12) },
      Tree(name: "works-list-1400") { worksList(rows: 200) },
      Tree(name: "works-list-20000") { worksList(rows: 3000) },
    ]
  }

  // MARK: Views

  @MainActor private static func rendered<V: View>(_ view: V) -> _RenderNode {
    StaticHTMLFiberRenderer().renderTree(view).root.renderNode
  }

  private struct FormScreen: View {
    @State var name = "Ada"
    @State var on = true
    @State var level = 0.4
    @State var choice = 1
    var body: some View {
      Form {
        Section("Account") {
          TextField("Name", text: $name)
          Toggle("Notifications", isOn: $on)
          Slider(value: $level)
          Picker("Choice", selection: $choice) { Text("One").tag(1); Text("Two").tag(2) }
        }
        Section {
          Button("Save") {}
          Link("Docs", destination: URL(string: "https://example.com/docs?a=1&b=2")!)
        }
      }
    }
  }

  private struct ListScreen: View {
    var body: some View {
      NavigationStack {
        List {
          ForEach(0..<30, id: \.self) { index in
            HStack {
              Image(systemName: "star.fill").foregroundColor(.yellow)
              VStack(alignment: .leading) {
                Text("Row \(index) <b>&</b>").font(.headline)
                Text("Detail \(index)").font(.caption).foregroundColor(.secondary)
              }
              Spacer()
              Text("\(index * 3)").monospacedDigit()
            }
            .padding(.vertical, 4)
          }
        }
        .navigationTitle("Items")
      }
    }
  }

  private struct TabsScreen: View {
    @State var selection = 0
    var body: some View {
      TabView(selection: $selection) {
        Text("Home").tabItem { Label("Home", systemImage: "house") }.tag(0)
        ScrollView { VStack { ForEach(0..<8, id: \.self) { Text("Line \($0)").padding() } } }.tabItem { Label("Feed", systemImage: "list.bullet") }.tag(1)
        Color.blue.tabItem { Label("Color", systemImage: "paintpalette") }.tag(2)
      }
    }
  }

  private struct ShapesScreen: View {
    var body: some View {
      ZStack {
        Circle().fill(Color.red).frame(width: 40, height: 40)
        RoundedRectangle(cornerRadius: 8).stroke(Color.blue, lineWidth: 2).frame(width: 60, height: 60)
        Capsule().fill(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)).frame(width: 80, height: 20)
        Rectangle().fill(.ultraThinMaterial).frame(width: 30, height: 30).opacity(0.5).rotationEffect(.degrees(15)).offset(x: 4, y: 4)
      }
    }
  }

  private struct GridScreen: View {
    var body: some View {
      VStack {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.adaptive(minimum: 40))]) {
          ForEach(0..<12, id: \.self) { Text("Cell \($0)").frame(maxWidth: .infinity).background(Color.gray.opacity(0.2)) }
        }
        Grid { GridRow { Text("a"); Text("b") }; GridRow { Text("c"); Text("d") } }
        ProgressView(value: 0.3)
        ProgressView()
        Divider()
        Label("Label & text", systemImage: "tag")
        Text("Underlined \u{1F600} café").underline().italic().bold().kerning(1).lineLimit(2).multilineTextAlignment(.center)
      }
      .padding()
    }
  }

  private struct ModifiersScreen: View {
    @State var showing = true
    var body: some View {
      VStack(spacing: 12) {
        Text("Hover me").onHover { _ in }.onTapGesture {}.help("A help \"title\"")
        if showing { Text("Shown").transition(.opacity) } else { EmptyView() }
        Text("Shadow").shadow(color: .black, radius: 2, x: 1, y: 1).cornerRadius(4).border(Color.green, width: 1)
        Button { showing.toggle() } label: { Text("Toggle") }.buttonStyle(.borderedProminent).disabled(false)
        Group { Text("g1"); Text("g2") }.accessibilityLabel("group <label>")
        HStack { Color.red; Color.green; Color.blue }.frame(height: 20)
        Text("Tap").contextMenu { Button("One") {}; Button("Two") {} }
        GeometryReader { proxy in Text("w \(Int(proxy.size.width))") }
      }
    }
  }

  static var views: [Tree] {
    [
      Tree(name: "view-text-modifiers") { rendered(Text("<hello> & \"world\"").foregroundColor(.red).padding(4).background(Color.yellow)) },
      Tree(name: "view-stacks") {
        rendered(VStack(spacing: 2) { Text("Header"); HStack { Text("L"); Spacer(); Text("R") }; ZStack { Color.red; Text("Over") } })
      },
      Tree(name: "view-form") { rendered(FormScreen()) },
      Tree(name: "view-list-navigation") { rendered(ListScreen()) },
      Tree(name: "view-tabs") { rendered(TabsScreen()) },
      Tree(name: "view-shapes") { rendered(ShapesScreen()) },
      Tree(name: "view-grid-misc") { rendered(GridScreen()) },
      Tree(name: "view-modifiers") { rendered(ModifiersScreen()) },
      Tree(name: "view-foreach-300") {
        rendered(ScrollView { LazyVStack { ForEach(0..<300, id: \.self) { index in HStack { Text("Row \(index)"); Spacer(); Image(systemName: "chevron.right") }.padding() } } })
      },
      Tree(name: "view-deep-stacks") {
        func nest(_ levels: Int) -> AnyView { levels == 0 ? AnyView(Text("leaf")) : AnyView(VStack(spacing: 0) { nest(levels - 1) }) }
        return rendered(nest(120))
      },
    ]
  }

  static var all: [Tree] { handBuilt + generated + views }
}
