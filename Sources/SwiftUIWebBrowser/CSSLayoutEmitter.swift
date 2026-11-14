@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

// CSS layout emitted by Swift: the analysis `Tools/css-layout.js` makes of the published DOM, made here of the fiber tree
// before it is published, for the application's root view (the window root). Each element gets the declaration block CSS
// lays it out with, as a rule of its own (`.sl<n>`) whose class the element carries, and the root a marker
// (`data-sl-root`); the rules ride on the root (`data-sl-rules`) until the host acknowledges the publication that
// carried them. The page's
// mapper then leaves that root alone, and the main thread does none of the analysis. See "Swift emits the CSS" in
// Documentation/Architecture/CSS_LAYOUT.md.
//
// The port follows the JS mapper function for function (`kindOf`, `analyse`, `size`, `chainPlan`, `declarations`,
// `placement`, `grid`, `layer`, `rootPlacement`, `barItem`, `assign`) and writes the same declaration blocks, character
// for character: with `window.__layoutVerify` the page compares every block with a fresh analysis of its own.

/// A published element as the page's DOM has it: its tag, classes, attributes and inline display, and its child elements
/// (fragments flattened, empty nodes dropped). Built from a fiber and what the snapshot adds to the copy it publishes.
@MainActor final class _CSSElement {
  let fiber: Fiber
  let tag: String
  let classes: [String]
  let attributes: _NodeValues
  let inlineDisplay: String?
  /// The inline width and height its Swift view authored (a custom SF Symbol's, in em).
  let inlineWidth: String?
  let inlineHeight: String?
  /// Inside a text leaf (`data-layout-leaf="text"`): the snapshot publishes such text without layout attributes.
  let insideTextLeaf: Bool
  let insideButton: Bool
  /// Whether a LabeledContent cell (`data-cell-kind="labeled"`) holds this element, where a text keeps its words whole.
  var insideLabeledCell = false
  private var childList: [_CSSElement]?
  private var textCache: String?

  init(fiber: Fiber, insideTextLeaf: Bool, insideButton: Bool, parentTag: String) {
    self.fiber = fiber
    let node = fiber.renderNode
    var attributes = node.attributes
    var tag = "span"
    switch node.kind {
    case .element(let name):
      tag = name
      // The HTML parser never nests a <button> in a <button>: the snapshot publishes the inner one as a div.
      if insideButton, name == "button" { tag = "div"; attributes["role"] = attributes["role"] ?? "button" }
    case .text:
      let textOnlyParent = ["option", "textarea", "title", "script", "style", "text", "tspan"].contains(parentTag)
      if !textOnlyParent && !insideTextLeaf {
        attributes["data-layout-kind"] = "intrinsic"
        attributes["data-layout-leaf"] = "text"
      }
    default: break
    }
    self.tag = tag
    self.classes = node.classes
    self.attributes = attributes
    self.inlineDisplay = node.styles["display"]
    self.inlineWidth = node.styles["width"]
    self.inlineHeight = node.styles["height"]
    self.insideTextLeaf = insideTextLeaf
    self.insideButton = insideButton
  }

  func attr(_ name: String) -> String? { attributes[name] }
  func has(_ name: String) -> Bool { attributes[name] != nil }
  func hasClass(_ name: String) -> Bool { classes.contains(name) }

  /// The element children, as `element.children` lists them.
  var children: [_CSSElement] {
    if let list = childList { return list }
    var list: [_CSSElement] = []
    let childLeaf = insideTextLeaf || attributes["data-layout-leaf"] == "text"
    let childButton = insideButton || tag == "button"
    let childLabeled = insideLabeledCell || attributes["data-cell-kind"] == "labeled"
    // A loop over an explicit stack, in document order: fragments are expanded in place, and their depth follows the
    // view tree, which can be as deep as the data it was built from.
    var pending = Array(fiber.children.reversed())
    while let child = pending.popLast() {
      switch child.renderNode.kind {
      case .empty: continue
      case .fragment: pending.append(contentsOf: child.children.reversed())
      case .text:
        // Plain text is a text node; one with attributes (all the snapshot publishes outside text-only parents) a span.
        let textOnlyParent = ["option", "textarea", "title", "script", "style", "text", "tspan"].contains(tag)
        if textOnlyParent { continue }
        let element = _CSSElement(fiber: child, insideTextLeaf: childLeaf, insideButton: childButton, parentTag: tag)
        element.insideLabeledCell = childLabeled
        list.append(element)
      case .element:
        let element = _CSSElement(fiber: child, insideTextLeaf: childLeaf, insideButton: childButton, parentTag: tag)
        element.insideLabeledCell = childLabeled
        list.append(element)
      }
    }
    childList = list
    return list
  }

  /// `element.textContent`.
  var textContent: String {
    if let text = textCache { return text }
    var out = ""
    var pending = [fiber]
    while let current = pending.popLast() {
      if case .text = current.renderNode.kind { out += current.renderNode.text ?? "" }
      pending.append(contentsOf: current.children.reversed())
    }
    textCache = out
    return out
  }

  /// `element.querySelector(selectors)` for a list of tag names: whether a descendant element has one of them.
  func hasDescendant(tags: [String]) -> Bool {
    var pending = children
    while let element = pending.popLast() {
      if tags.contains(element.tag) { return true }
      pending.append(contentsOf: element.children)
    }
    return false
  }
}

/// How a node's size relates to the proposal on one axis (`size` in the JS mapper).
struct _CSSAxis {
  var fixed: Double?
  var min: Double?
  var max: Double?
  var fill = false
  var rigid = false
  /// A fill that an HStack does not grow along its axis (SwiftUI gives such a view the same width at a zero
  /// and at an unlimited proposal), as a List row's link that takes the row's width.
  var soft = false
  var cap: Double?
  /// A finite maximum kept where the node is proposed nothing and hugs what it holds (`frame(maxHeight:)`).
  var hugMax: Double?
  var capIdeal: Double?
  /// Among a stack's views, offered at most its content's ideal size (a LabeledContent row's answer to an unlimited proposal).
  var capContent = false
  var ideal = false
}

struct _CSSEdges {
  var top = 0.0, leading = 0.0, bottom = 0.0, trailing = 0.0
  var isZero: Bool { top == 0 && leading == 0 && bottom == 0 && trailing == 0 }
}

struct _CSSRange { var min: Double; var max: Double?; var filled: Bool }
struct _CSSAxisPlan { var track: String; var content: Double; var item: Double; var range: _CSSRange?; var fit: Bool; var least: Double }
struct _CSSPlan { var pad: _CSSEdges; var margin: _CSSEdges; var x: _CSSAxisPlan; var y: _CSSAxisPlan }
struct _CSSTrack { var type: String; var min: Double; var max: Double; var spacing: Double?; var ax: Double?; var ay: Double? }
struct _CSSBarItem { let element: _CSSElement; let shown: Bool; let side: String }

/// An analysed node (`analyse` in the JS mapper): an element, or a layer of an element's run of layout modifiers.
/// One element whose analysis has begun (`_CSSLayoutEmitter.analyse`): the children it waits for, and the next one.
@MainActor final class _CSSAnalysisFrame {
  let node: _CSSNode
  let children: [_CSSElement]
  var next = 0
  init(node: _CSSNode, children: [_CSSElement]) { self.node = node; self.children = children }
}

@MainActor final class _CSSNode {
  let element: _CSSElement
  let kind: String
  /// A layer's attributes (`data-layout-wrap`); an element's are its own.
  let layerAttributes: _NodeValues?
  var kids: [_CSSNode] = []
  var supported: Bool
  /// The `.sidebarAdaptable` tab views in this subtree (their sidebar slots are roots of their own).
  var tabViews: [_CSSElement] = []
  /// The NavigationSplitViews in this subtree (a `flexible` leaf whose columns' content are roots of their own).
  var splitViews: [_CSSElement] = []
  /// The presentations (`.presentation-root`) this subtree holds: what they present is a root of its own.
  var presentations: [_CSSElement] = []
  /// Children a collapsed rail hides (`.hstack > :not(:first-child)` in the bottom bar's slot): `display: none` there.
  var railHidden: [_CSSElement] = []
  /// Takes `kid` as its next child: CSS can lay this node out only if it can lay out all it holds.
  func adopt(_ kid: _CSSNode) {
    kids.append(kid)
    if !kid.supported { supported = false }
  }
  var x = _CSSAxis(), y = _CSSAxis()
  /// Whether a Divider directly in this node runs vertically (`runsVertical`), and, for a Divider (an `hr`), whether it does.
  var runsVertical = false
  var isDivider = false, vertical = false
  var layers: [_CSSNode]?
  var plan: _CSSPlan?
  var ax = 0.5, ay = 0.5
  var baseline = false
  var explicitPriority = false
  var priority = 0.0
  var spacing = 8.0
  var ctxKey = ""
  var ctxKeyBase = ""
  var tracks: [_CSSTrack] = []
  var cell = 0
  var cols = 0
  var colFill: [Bool] = []
  /// A GridRow's cell: the column it starts in and the columns it covers; a table's rows: the width in columns and each column's alignment.
  var col = 0
  var span = 1
  var width = 0
  var colAlign: [String?] = []
  var rowAy: Double?
  var tableAlign: (Double, Double) = (0.5, 0.5)
  var hasTableAlign = false
  var bar: [_CSSBarItem] = []
  var extent: (Double, Double) = (0, 0)
  var defX = false, defY = false
  /// An aspect box: the height the frames and paddings around it propose to it, when they do (`aspectCap`).
  var cap: Double?
  /// The height this frame, padding or fixedSize (or the run of them its element carries, up to this layer) proposes to what it
  /// holds, when it is proposed none (`passHeight`): infinity if it proposes none; nil for any other node.
  var heightOut: Double?
  var margin: _CSSEdges?
  var applied: Int?
  var ctxSeen: String?
  var version: UInt64 = 0

  init(element: _CSSElement, kind: String, layerAttributes: _NodeValues? = nil) {
    self.element = element
    self.kind = kind
    self.layerAttributes = layerAttributes
    self.supported = !_cssUnsupported.contains(kind)
  }

  func attr(_ name: String) -> String? {
    if let layer = layerAttributes { return layer[String(name.dropFirst(5))] }
    return element.attr(name)
  }
  func axis(_ a: Character) -> _CSSAxis { a == "x" ? x : y }
  /// A canvas that carries its own frame (`frame(...)` keeps the element): the drawing it holds is a flexible leaf with no
  /// element of its own.
  var isFramedCanvas: Bool { kind == "frame" && layerAttributes == nil && element.tag == "canvas" && element.children.isEmpty }
}

/// The longhands a block's shorthand declarations cover.
private let _cssLonghands: [String: [String]] = [
  "margin": ["margin-top", "margin-right", "margin-bottom", "margin-left"],
  "padding": ["padding-top", "padding-right", "padding-bottom", "padding-left"],
  "inset": ["top", "right", "bottom", "left"],
  "flex": ["flex-grow", "flex-shrink", "flex-basis"],
  "gap": ["row-gap", "column-gap"],
  "grid-area": ["grid-row", "grid-column", "grid-row-start", "grid-row-end", "grid-column-start", "grid-column-end"],
  "place-items": ["align-items", "justify-items"],
]
private let _cssUnsupported: Set<String> = ["fit", "container-relative"]
private let _cssLeaves: Set<String> = ["intrinsic", "opaque", "field", "flexible", "spacer", "size"]
private let _cssLayerKinds: Set<String> = ["frame", "padding", "fixed"]
private let _cssFlex = ["flex-start", "center", "flex-end"]
/// The kinds a Divider inside them still runs along the stack around them (`RUNS_THROUGH` of the JS mapper): `Divider().frame(height: 20)`
/// is a vertical rule in an HStack, as is one with a padding, a fixedSize or an overlay; a ZStack, a VStack and the rest start over.
private let _cssRunsThrough: Set<String> = ["frame", "padding", "fixed", "overlay", "background"]
/// The height of a linear ProgressView's track (`PROGRESS_TRACK` of the JS mapper): the 8 px its view authors (and the host measures),
/// which the published DOM no longer carries when Swift emitted the block that overrides it.
private let _cssProgressTrack = 8.0
/// Whether a Divider directly in a node of `kind` held by `parent` runs vertically: its stack is an HStack (`runsVertical`).
@MainActor private func _cssRunsVertical(_ kind: String, _ parent: _CSSNode?) -> Bool { kind == "hstack" || (_cssRunsThrough.contains(kind) && parent?.runsVertical == true) }
private let _cssGrid = ["start", "unsafe center", "unsafe end"]

/// `Number(v)` of the JS mapper's `num`: `inf` is infinity, an empty or missing value is `fallback`.
func _cssNum(_ value: String?, _ fallback: Double? = nil) -> Double? {
  guard let value, !value.isEmpty else { return fallback }
  if value == "inf" { return Double.infinity }
  return Double(value) ?? fallback
}

/// A number as JavaScript prints it (`String(v)`): integers without a fraction, the shortest digits otherwise.
func _cssJS(_ value: Double) -> String {
  if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
  if value == 0 { return "0" }
  if value == value.rounded(), Swift.abs(value) < 1e21 {
    if Swift.abs(value) < 9.0e18 { return String(Int64(value)) }
  }
  var text = String(value)
  // Swift prints `1e-07`, JavaScript `1e-7`.
  if let e = text.firstIndex(of: "e") {
    let mantissa = text[..<e]
    var exponent = String(text[text.index(after: e)...])
    var sign = "+"
    if exponent.hasPrefix("-") { sign = "-"; exponent.removeFirst() } else if exponent.hasPrefix("+") { exponent.removeFirst() }
    while exponent.count > 1, exponent.hasPrefix("0") { exponent.removeFirst() }
    text = String(mantissa) + "e" + sign + exponent
  }
  if text.hasSuffix(".0") { text.removeLast(2) }
  return text
}

/// Whether `text` holds `needle` (`String.contains` of a string needs Foundation in Embedded Swift).
func _cssHas(_ text: String, _ needle: String) -> Bool {
  let h = Array(text.utf8), n = Array(needle.utf8)
  guard !n.isEmpty, h.count >= n.count else { return n.isEmpty }
  var i = 0
  while i + n.count <= h.count {
    var j = 0
    while j < n.count && h[i + j] == n[j] { j += 1 }
    if j == n.count { return true }
    i += 1
  }
  return false
}

/// Whether `String.prototype.trim` leaves nothing of `text`.
func _cssBlank(_ text: String) -> Bool {
  for scalar in text.unicodeScalars {
    switch scalar.value {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: continue
    default: return false
    }
  }
  return true
}

/// `px` of the JS mapper: rounded to 1/64.
func _cssPx(_ value: Double) -> String { _cssJS((value * 64).rounded(.toNearestOrAwayFromZero) / 64) + "px" }

/// `vpx` of the JS mapper: a length that can change with every step of a resize, a scroll or an animation (a frame's size, a
/// position, a lazy extent), marked for `_cssLengthVariables`. The rule of a block carries `var(--len<i>)` where it stands and the
/// element the values, so a new value rewrites one inline declaration and adds no rule (a rule inserted in a stylesheet invalidates
/// the style of the whole document).
func _cssVpx(_ value: Double) -> String { "\u{1}" + _cssPx(value) + "\u{2}" }

/// `lengthVariables` of the JS mapper: the rule text of a block that `_cssVpx` marked, and its lengths in order (`--len<i>` is the
/// i-th). With `variables` false (a collapsed rail's block, whose element already carries the lengths of its expanded one) the
/// lengths stay in the text and the list is empty.
func _cssLengthVariables(_ block: String, variables: Bool = true) -> (text: String, lengths: [String]) {
  var text: [UInt8] = [], length: [UInt8] = [], lengths: [String] = []
  var inside = false
  for byte in block.utf8 {
    if byte == 1 { inside = true; length = [] }
    else if byte == 2 && inside {
      inside = false
      if variables {
        lengths.append(String(decoding: length, as: UTF8.self))
        text.append(contentsOf: Array("var(--len\(lengths.count - 1))".utf8))
      } else { text.append(contentsOf: length) }
    } else if inside { length.append(byte) }
    else { text.append(byte) }
  }
  return (String(decoding: text, as: UTF8.self), lengths)
}

private func _cssSide(_ a: Double) -> Int { a <= 0.25 ? 0 : a >= 0.75 ? 2 : 1 }
private func _cssAlign(_ value: String?) -> Double {
  let v = value ?? ""
  if _cssHas(v, "start") || _cssHas(v, "leading") || _cssHas(v, "top") { return 0 }
  if _cssHas(v, "end") || _cssHas(v, "trailing") || _cssHas(v, "bottom") { return 1 }
  return 0.5
}
/// Whether `_cssWeight` is exact for `priority`: whole and half priorities. `Math.pow(1e6, p + 1)` of any other is
/// rounded as the engine rounds it (the page's differs from engine to engine in the last digit), which no port can repeat.
private func _cssExactWeight(_ priority: Double) -> Bool {
  let steps = (Swift.min(Swift.max(priority, -1), 3) + 1) * 2
  return steps == steps.rounded()
}
/// The `weight` of the JS mapper (`1e6 ^ (priority + 1)`, the priority clamped to -1...3): a flex-grow tier per layout
/// priority. Whole and half priorities (`1e6 ^ 1.5` is `1e9`, exactly); `analyse` refuses a node with another one.
private func _cssWeight(_ priority: Double) -> Double {
  var result = 1.0
  var steps = (Swift.min(Swift.max(priority, -1), 3) + 1) * 2
  while steps >= 1 { result *= 1_000; steps -= 1 }
  return result
}

// MARK: - Analysis

/// Whether a NavigationStack shows a pushed destination: its depth is authoritative, not the root's `aria-hidden`
/// (`pushedStack` of the JS mapper). The root then takes no part.
@MainActor private func _cssPushedStack(_ e: _CSSElement) -> Bool { (Double(e.attr("data-navigation-depth") ?? "") ?? 0) > 0 }
/// The shown items of a NavigationStack's bar on one side (`shownOn` of the JS mapper).
@MainActor private func _cssShownOn(_ n: _CSSNode, _ side: String) -> [_CSSBarItem] { n.bar.filter { $0.shown && $0.side == side } }
/// The tracks of a NavigationStack's bar grid (`barTracks` of the JS mapper): one per item on a side that holds several, and one
/// per principal item when there are several. Nil when no side needs one.
@MainActor private func _cssBarTracks(_ n: _CSSNode) -> (lead: Int, centre: Int, trail: Int)? {
  let start = _cssShownOn(n, "start").count, centre = _cssShownOn(n, "center").count, end = _cssShownOn(n, "end").count
  if centre > 1 { return (start > 1 ? start : 0, centre, end > 1 ? end : 0) }
  return start < 2 && end < 2 ? nil : (start, 0, end)
}
/// The columns of that grid (`barColumns` of the JS mapper).
@MainActor private func _cssBarColumns(_ n: _CSSNode) -> String? {
  guard let t = _cssBarTracks(n) else { return nil }
  let middle = t.centre > 0 ? ["1fr"] + Array(repeating: "auto", count: t.centre) + ["minmax(0,1fr)"] : ["minmax(0,1fr)"]
  return (Array(repeating: "auto", count: t.lead) + middle + Array(repeating: "auto", count: t.trail)).joined(separator: " ")
}

/// The grid area of a shown bar item (`barArea` of the JS mapper).
@MainActor private func _cssBarArea(_ n: _CSSNode, _ item: _CSSBarItem) -> String {
  guard let t = _cssBarTracks(n) else { return "1 / 1" }
  let index = _cssShownOn(n, item.side).firstIndex { $0.element.fiber === item.element.fiber } ?? 0
  if item.side == "center" { return t.centre > 0 ? "1 / " + String(t.lead + 2 + index) : "1 / 1 / 2 / -1" }
  if item.side == "start" { return "1 / " + String(index + 1) }
  return t.trail > 0 ? "1 / " + String(t.lead + 2 + (t.centre > 0 ? t.centre + 1 : 0) + index) : "1 / 1 / 2 / -1"
}

/// A safeAreaInset (or a TabView's bottom tab bar): its inset's edge, whether that edge is vertical (top or bottom: the
/// inset is a row), and whether it is the start (top or leading) (`insetEdge` of the JS mapper).
@MainActor private func _cssInsetEdge(_ n: _CSSNode) -> (vertical: Bool, start: Bool) {
  let edge = n.attr("data-inset-edge") ?? "bottom"
  return (edge == "top" || edge == "bottom", edge == "top" || edge == "leading")
}

/// The grid area of an inset's child (`insetArea` of the JS mapper).
@MainActor private func _cssInsetArea(_ parent: _CSSNode, _ n: _CSSNode) -> String {
  let (vertical, start) = _cssInsetEdge(parent)
  let first = (parent.kids.count > 1 && parent.kids[1] === n) == start
  return vertical ? (first ? "1" : "2") + " / 1" : "1 / " + (first ? "1" : "2")
}

/// The bar `NavigationStack` builds from `ToolbarItemPlacement.bottomBar` items: a row of its own below the screen.
@MainActor private func _cssIsBottomBar(_ e: _CSSElement) -> Bool { e.hasClass("navigation-bottom-bar") }
@MainActor private func _cssIsToolbarChrome(_ e: _CSSElement) -> Bool { e.hasClass("toolbar-item") || e.hasClass("toolbar-group") }
@MainActor private func _cssBarSide(_ e: _CSSElement) -> String {
  let p = e.attr("data-toolbar-placement") ?? ""
  return p == "principal" ? "center" : _cssHas(p, "leading") ? "start" : "end"
}
/// A tab panel built hidden before it was ever shown (`data-tab-prepared`) is laid out while hidden: the stylesheet keeps it
/// hidden, and the frame that shows it shows it in place instead of at the browser's defaults.
@MainActor private func _cssTakesPart(_ child: _CSSElement) -> Bool {
  !child.has("hidden") && !child.hasClass("swipe-actions") && child.attr("data-navigation-inactive") != "true" &&
    (child.attr("data-tab-hidden") != "true" || child.attr("data-tab-prepared") == "true") && !child.hasClass("presentation-root") && !child.hasClass("swiftuiweb-navigation-bar") &&
    !child.hasClass("context-menu-panel") && !child.hasClass("toolbar-item") && !child.hasClass("toolbar-group") &&
    !child.has("data-layout-hidden")
}

/// `kindOf` of the JS mapper.
@MainActor func _cssKind(_ e: _CSSElement) -> String {
  if e.hasClass("tab-view") && e.attr("data-tab-style") == "sidebar-adaptable" { return "tabview" }
  if let explicit = e.attr("data-layout-kind"), !explicit.isEmpty { return explicit }
  if e.has("data-geometry-reader") { return "geometry" }
  if e.has("data-view-that-fits") { return "fit" }
  if e.hasClass("scroll-view") { return "scroll" }
  // A NavigationStack (or the legacy NavigationView, whatever its tag): its bar is a row above the screen on top.
  if e.hasClass("navigation-stack") || e.hasClass("navigation-view") { return "navstack" }
  if e.hasClass("tab-body") || e.hasClass("tab-panel") || e.hasClass("navigation-destination") { return "panel" }
  if e.tag == "button" && (e.hasClass("button-plain") || e.hasClass("button-borderless") || e.hasClass("button-custom")) { return "zstack" }
  if e.tag == "input" && e.attr("data-field-chrome") == "plain" { return "field" }
  // A linear Gauge takes the width it is offered and is as tall as its track, which the stylesheet stretches across it.
  if e.hasClass("gauge-meter") { return "field" }
  // A linear ProgressView and a Slider take the width they are offered too and are as tall as their track.
  if e.tag == "progress" || (e.tag == "input" && e.attr("type") == "range") { return "field" }
  if e.hasClass("layout-box") || e.hasClass("regular-grid") || e.hasClass("table-view") || ["button", "input", "textarea", "select", "details", "table", "ul", "ol", "label"].contains(e.tag) { return "opaque" }
  if e.hasClass("avkit-video-player") || e.hasClass("data-chart") || e.hasClass("shape-layer") || e.hasClass("mesh-gradient") || ["canvas", "iframe", "video"].contains(e.tag) || e.attr("data-resizable") == "true" { return "flexible" }
  if e.hasClass("backdrop-layer") { return "background" }
  if e.hasClass("overlay-layer") { return "overlay" }
  if e.hasClass("vstack") || e.hasClass("searchable") { return "vstack" }
  if e.hasClass("hstack") { return "hstack" }
  if e.hasClass("zstack") { return "zstack" }
  if e.hasClass("swipe-row") || e.hasClass("swipe-content") { return "zstack" }
  if e.hasClass("grid-layout") { return "grid" }
  if e.hasClass("scroll-view-reader") || e.hasClass("lazy-cell") || e.hasClass("navigation-root") || e.hasClass("timeline-view") || e.hasClass("layout-item") { return "zstack" }
  return e.children.isEmpty ? "intrinsic" : "opaque"
}

/// `data-layout-wrap`: `kind;name=value;...` per layer, outermost first, separated by `|`.
private func _cssParseLayers(_ text: String) -> [(String, _NodeValues)] {
  text.split(separator: "|", omittingEmptySubsequences: false).map { part in
    let pieces = part.split(separator: ";", omittingEmptySubsequences: false)
    var map: _NodeValues = [:]
    for pair in pieces.dropFirst() {
      if let i = pair.firstIndex(of: "="), i != pair.startIndex { map[String(pair[..<i])] = String(pair[pair.index(after: i)...]) }
    }
    return (pieces.first.map(String.init) ?? "", map)
  }
}

/// What the container of a root island proposes it (`claimRoot` in the JS mapper): the window.
/// What the container of a root proposes it, as `cssRootProposal` in `Tools/layout-host.js` works it out: whether there is a
/// proposal on each axis, the horizontal alignment there, and the height a finite vertical proposal is (a CSS length, or
/// `cell` for a one-cell grid the container is made into).
struct _CSSRootProposal {
  var defX = true, defY = true, ax = 0.5, height = "100dvh"
  /// The application's root view: the window (its width and `100dvh`), centred.
  static let window = _CSSRootProposal()
  /// An expanded sidebar slot's content: the slot's width, its own height, leading.
  static let slot = _CSSRootProposal(defX: true, defY: false, ax: 0, height: "auto")
  /// A collapsed rail's slot content: the rail's width, its own height, centred.
  static let rail = _CSSRootProposal(defX: true, defY: false, ax: 0.5, height: "auto")
  /// A NavigationSplitView column's content: the column's content box (a flex column of definite height), centred.
  static let column = _CSSRootProposal(defX: true, defY: true, ax: 0.5, height: "100%")
  /// A presentation's content that holds the root alone: its content box, centred.
  static let presentation = _CSSRootProposal(defX: true, defY: true, ax: 0.5, height: "cell")
}

/// A presentation's content (`.presentation-content`) and the root it holds, when it holds that root alone (the page's
/// `cssRootProposal`).
@MainActor private func _cssPresentationRoot(in presentation: _CSSElement) -> (_CSSElement, _CSSElement)? {
  var stack = [presentation]
  while let e = stack.popLast() {
    if e.hasClass("presentation-content") {
      let children = e.children
      return children.count == 1 ? (e, children[0]) : nil
    }
    stack.append(contentsOf: e.children.reversed())
  }
  return nil
}

/// The content roots of a tab view's sidebar slots (`data-tab-sidebar-content`), with each slot's placement.
@MainActor private func _cssSidebarSlotRoots(of tabView: _CSSElement) -> [(String, _CSSElement)] {
  guard let sidebar = tabView.children.first(where: { $0.attr("data-tab-sidebar") == "true" }) else { return [] }
  var out: [(String, _CSSElement)] = []
  var stack = [sidebar]
  while let e = stack.popLast() {
    if let placement = e.attr("data-tab-sidebar-content") {
      for root in e.children { out.append((placement, root)) }
      continue
    }
    stack.append(contentsOf: e.children.reversed())
  }
  return out
}

@MainActor final class _CSSLayoutEmitter {
  static let shared = _CSSLayoutEmitter()
  /// Whether the page asked for CSS layout (`embedded_browser_css_layout`).
  var enabled = false
  /// Called as the analysis and the styling reach each node (tests measure how deep a call stack they use).
  static var stackProbe: (@MainActor () -> Void)?
  /// How many distinct blocks the emitter writes before it stops styling (see `run`).
  var blockLimit = 8192
  private var cache: [ObjectIdentifier: _CSSNode] = [:]
  /// The analyses of a collapsed rail's slot content: nodes of their own, which carry the rail's blocks.
  private var railCache: [ObjectIdentifier: _CSSNode] = [:]
  /// Whether the analysis under way is a collapsed rail's, and whether its slot hides an `.hstack`'s later children.
  private var analysingRail = false, railHidesStackTail = false
  private var blocks: [String: Int] = [:]
  private var texts: [String] = [""]
  /// Rule ids by the epoch they were first published at, until the host acknowledges it.
  private var unacknowledged: [(id: Int, rail: Bool, epoch: UInt64)] = []
  /// Block id each element fiber carries now.
  private(set) var assigned: [ObjectIdentifier: Int] = [:]
  /// The lengths each element carries for its block's `var(--len<i>)` (`_cssLengthVariables`); an element with none is absent.
  private(set) var assignedLengths: [ObjectIdentifier: [String]] = [:]
  /// Block id each element of a sidebar slot carries in a collapsed rail (a rule scoped to the rail, `.sr<n>`).
  private(set) var railAssigned: [ObjectIdentifier: Int] = [:]
  /// Fibers whose block, or a block below them, changed in the last run: their subtree cannot be a keep placeholder.
  private(set) var changed: Set<ObjectIdentifier> = []
  /// The roots CSS lays out (their element fibers): the window root, sidebar slots' content and presentations' content.
  private(set) var roots: Set<ObjectIdentifier> = []
  /// The presentations' content elements made one-cell grids for their root (`data-cl-host`).
  private(set) var hosts: Set<ObjectIdentifier> = []
  var analysedCount = 0

  // MARK: analyse

  /// The analysis of `root` and of what it holds. The tree is walked with a stack of its own, children before their
  /// parent, not one call per level: a Worker's call stack is far smaller than the main thread's, and a deep view tree
  /// overflowed it (the runtime then moves the app to the main thread for the rest of the session).
  func analyse(_ root: _CSSElement) -> _CSSNode {
    if let cached = cachedAnalysis(root, parent: nil) { return cached }
    var stack = [beginAnalysis(root, parent: nil)]
    while let frame = stack.last {
      if frame.next < frame.children.count {
        let child = frame.children[frame.next]
        frame.next += 1
        if let cached = cachedAnalysis(child, parent: frame.node) { frame.node.adopt(cached) } else { stack.append(beginAnalysis(child, parent: frame.node)) }
        continue
      }
      stack.removeLast()
      finishAnalysis(frame.node)
      guard let parent = stack.last else { return frame.node }
      parent.node.adopt(frame.node)
    }
    fatalError("unreachable")
  }

  /// The analysis of `e` kept from an earlier run, while `e`'s subtree is unchanged. A subtree's version says whether
  /// anything below it changed, except in a volatile one (a lazy window is rebuilt at every publication,
  /// `Fiber.isVolatile`), which is analysed again.
  private func cachedAnalysis(_ e: _CSSElement, parent: _CSSNode?) -> _CSSNode? {
    guard let cached = (analysingRail ? railCache : cache)[ObjectIdentifier(e.fiber)], cached.version == e.fiber.version, !e.fiber.isVolatile,
          cached.element.tag == e.tag else { return nil }
    // A Divider runs along the stack around it, which can change without the Divider changing.
    guard cached.runsVertical == _cssRunsVertical(cached.kind, parent), !cached.isDivider || cached.vertical == (parent?.runsVertical == true) else { return nil }
    return cached
  }

  /// What `e` is, before its children are analysed: its node, and the children that take part in its layout.
  private func beginAnalysis(_ e: _CSSElement, parent: _CSSNode?) -> _CSSAnalysisFrame {
    Self.stackProbe?()
    analysedCount += 1
    let kind = _cssKind(e)
    let node = _CSSNode(element: e, kind: kind)
    node.version = e.fiber.version
    // A Divider (an `hr`) is a line across the stack it is in: vertical in an HStack, horizontal anywhere else.
    node.runsVertical = _cssRunsVertical(kind, parent)
    if kind == "intrinsic" && e.tag == "hr" { node.isDivider = true; node.vertical = parent?.runsVertical == true }
    // A documentation page lays out its examples where the page puts them (`data-native-layout`): the page's mapper takes
    // each example's preview as a root of its own (`cssRootProposal`: its container's width, nothing along the height), and
    // Swift refuses what holds the attribute.
    if e.has("data-native-layout") { node.supported = false }
    // A user-defined Layout (Swift places its subviews at the proposal the host reports): the host lays out
    // what holds one.
    if e.hasClass("layout-box") && e.has("data-layout-proposal") { node.supported = false }
    let container = !_cssLeaves.contains(kind)
    if kind == "navstack" {
      node.bar = e.children.filter(_cssIsToolbarChrome).map { item in
        _CSSBarItem(element: item, shown: !_cssBlank(item.textContent) || item.hasDescendant(tags: ["button", "input", "select", "a", "img", "svg"]), side: _cssBarSide(item))
      }
    }
    var children: [_CSSElement] = []
    if container {
      // A collapsed rail's bottom bar hides an `.hstack`'s children after its first (the stylesheet's
      // `.hstack > :not(:first-child)`), unless an element's own inline `display` overrides that rule.
      let hidesTail = analysingRail && railHidesStackTail && e.hasClass("hstack")
      for (index, child) in e.children.enumerated() {
        if child.hasClass("presentation-root") { node.presentations.append(child); continue }
        guard _cssTakesPart(child) && (kind != "tabview" || child.hasClass("tab-body")) &&
          !(kind == "navstack" && child.hasClass("navigation-root") && _cssPushedStack(e)) else { continue }
        if hidesTail && index > 0 && (child.inlineDisplay ?? "").isEmpty { node.railHidden.append(child); continue }
        children.append(child)
      }
    }
    if e.hasClass("navigation-split-view") { node.splitViews.append(e) }
    // Below a leaf CSS does not lay out (a documentation page's content, a native widget) a presentation can still sit
    // where its modifier is: what it presents is a root of its own. Searched again only when the leaf's subtree changes.
    if !container && !e.children.isEmpty {
      var stack = e.children
      while let below = stack.popLast() {
        if below.hasClass("presentation-root") { node.presentations.append(below) } else { stack += below.children }
      }
    }
    return _CSSAnalysisFrame(node: node, children: children)
  }

  /// The rest of `node`'s analysis, once its children's are done.
  private func finishAnalysis(_ node: _CSSNode) {
    let e = node.element, kind = node.kind
    // A single-child modifier that holds several views (a List's rows in its ScrollView) stacks them, as the host does in a
    // vstack of its own, which its one grid cell does not express.
    // A ScrollView that does (a List's rows) is a grid of one column whose rows are its children (see `declarations`).
    if ["frame", "padding", "fixed", "aspect"].contains(kind) && node.kids.count > 1 { node.supported = false }
    let wrap = _cssLayerKinds.contains(kind) ? e.attr("data-layout-wrap") : nil
    if let wrap {
      var layers: [_CSSNode] = []
      for (layerKind, map) in _cssParseLayers(wrap) {
        let layer = _CSSNode(element: e, kind: layerKind, layerAttributes: map)
        layer.supported = true
        layer.ax = _cssNum(layer.attr("data-align-x"), 0.5) ?? 0.5
        layer.ay = _cssNum(layer.attr("data-align-y"), 0.5) ?? 0.5
        layers.append(layer)
      }
      node.layers = layers
    }
    if kind == "grid" {
      node.tracks = (e.attr("data-grid-tracks").flatMap { $0.isEmpty ? nil : $0 } ?? "flexible:10").split(separator: "|", omittingEmptySubsequences: false).map { t in
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        func part(_ i: Int) -> String? { i < parts.count ? parts[i] : nil }
        return _CSSTrack(type: part(0) ?? "", min: _cssNum(part(1), 0) ?? 0, max: _cssNum(part(2), .infinity) ?? .infinity,
                         spacing: _cssNum(part(3)), ax: _cssNum(part(4)), ay: _cssNum(part(5)))
      }
      var cell = 0
      for kid in node.kids { if kid.element.has("data-lazy-spacer") { kid.cell = -1 } else { kid.cell = cell; cell += 1 } }
    }
    if kind == "table" {
      let rows = node.kids.filter { $0.kind == "gridrow" }
      // A cell covers `data-grid-cell-columns` columns (gridCellColumns); a column is aligned as the first cell that starts in
      // it and names an alignment says (gridColumnAlignment).
      node.colAlign = []
      for row in rows {
        var col = 0
        for cell in row.kids {
          cell.col = col
          // Finite first: an "inf" read from the attribute is a span of 1, not the 1,000 the clamp would make it.
          let raw = _cssNum(cell.element.attr("data-grid-cell-columns"), 1) ?? 1
          cell.span = raw.isFinite ? max(1, Int(min(raw, 1_000).rounded(.down))) : 1
          if let alignment = cell.element.attr("data-grid-column-alignment"), !alignment.isEmpty {
            while node.colAlign.count <= col { node.colAlign.append(nil) }
            if node.colAlign[col] == nil { node.colAlign[col] = alignment }
          }
          col += cell.span
        }
        row.width = col
      }
      node.cols = rows.map { $0.width }.max() ?? 0
      node.colFill = (0..<node.cols).map { i in rows.contains { $0.kids.contains { $0.col == i && $0.span == 1 && $0.x.fill && !$0.x.soft } } }
    }
    if kind == "gridrow" { node.rowAy = _cssNum(e.attr("data-row-align-y")) }
    if kind == "table" { node.tableAlign = (_cssNum(e.attr("data-align-x"), 0.5) ?? 0.5, _cssNum(e.attr("data-align-y"), 0.5) ?? 0.5); node.hasTableAlign = true }
    node.ax = _cssNum(e.attr("data-align-x"), 0.5) ?? 0.5
    node.ay = _cssNum(e.attr("data-align-y"), 0.5) ?? 0.5
    if kind == "vstack" { node.ax = _cssNum(e.attr("data-align-x"), _cssAlign(e.attr("data-layout-alignment"))) ?? 0.5 }
    if kind == "hstack" { node.ay = _cssNum(e.attr("data-align-y"), _cssAlign(e.attr("data-layout-alignment"))) ?? 0.5 }
    node.baseline = false // the JS mapper's `baseline` option is off on the page
    node.explicitPriority = e.has("data-layout-priority")
    node.priority = _cssNum(e.attr("data-layout-priority"), 0) ?? 0
    if !_cssExactWeight(node.priority) { node.supported = false }
    node.spacing = e.hasClass("searchable") ? 0 : (_cssNum(e.attr("data-layout-gap"), 8) ?? 8)
    var key2 = kind + "|" + String(node.kids.count) + "|" + _cssJS(node.ax) + "|" + _cssJS(node.ay) + "|" + _cssJS(node.spacing)
    if let wrap { key2 += "|L" + wrap }
    if kind == "grid" { key2 += "|" + (e.attr("data-grid-tracks") ?? "") }
    if kind == "table" { key2 += "|" + String(node.cols) + node.colFill.map { $0 ? "true" : "false" }.joined() }
    if kind == "gridrow" { key2 += "|" + (node.rowAy.map(_cssJS) ?? "null") }
    if kind == "inset" { key2 += "|" + (e.attr("data-inset-edge") ?? "bottom") }
    if kind == "navstack" { key2 += "|" + node.bar.map { $0.shown ? $0.side : "-" }.joined(separator: ",") + "|" + (e.attr("data-navigation-title-display-mode") ?? "") }
    node.ctxKey = key2
    node.ctxKeyBase = key2
    if kind == "table" {
      for row in node.kids where row.kind == "gridrow" {
        row.tableAlign = node.tableAlign; row.hasTableAlign = true; row.colAlign = node.colAlign
        let cells = row.kids.map { String($0.span) + ":" + ($0.element.attr("data-grid-cell-anchor") ?? "") + ":" + ($0.element.attr("data-grid-unsized-axes") ?? "") }
        row.ctxKey = row.ctxKeyBase + "|T" + _cssJS(node.tableAlign.0) + "," + _cssJS(node.tableAlign.1) + "|C" + cells.joined(separator: ",") + "/" + node.colAlign.map { $0 ?? "" }.joined(separator: ",")
      }
    }
    // A canvas is its own frame boundary, so its frame has no child element: what the frame holds is the drawing, a
    // flexible leaf (the size only, it has no element of its own).
    var held = node.kids
    if kind == "frame" && e.tag == "canvas" && node.kids.isEmpty {
      let drawing = _CSSNode(element: e, kind: "flexible")
      drawing.x.fill = true; drawing.y.fill = true
      held = [drawing]
    }
    if let layers = node.layers {
      var i = layers.count - 1
      while i >= 0 { size(layers[i], kids: i == layers.count - 1 ? held : [layers[i + 1]]); i -= 1 }
      size(node, kids: [layers[0]])
      node.plan = chainPlan(node)
      if node.plan == nil { node.supported = false }
    } else {
      size(node, kids: held)
    }
    var tabViews: [_CSSElement] = kind == "tabview" ? [e] : []
    for kid in node.kids where !kid.tabViews.isEmpty { tabViews += kid.tabViews }
    node.tabViews = tabViews
    for kid in node.kids where !kid.presentations.isEmpty { node.presentations += kid.presentations }
    for kid in node.kids where !kid.splitViews.isEmpty { node.splitViews += kid.splitViews }
    if analysingRail { railCache[ObjectIdentifier(e.fiber)] = node } else { cache[ObjectIdentifier(e.fiber)] = node }
  }

  // MARK: size

  func size(_ n: _CSSNode, kids: [_CSSNode]) {
    let e = n.element, k = n.kind
    // A canvas is its own frame boundary, so a framed canvas has no child element; the host gives it a flexible leaf (`describeFresh`
    // in `layout-host.js`), which takes the frame's proposal.
    var kids = kids
    if n.isFramedCanvas {
      let content = _CSSNode(element: e, kind: "flexible")
      content.x.fill = true; content.y.fill = true
      kids = [content]
    }
    var x = _CSSAxis(), y = _CSSAxis()
    let primary: _CSSNode? = k == "overlay" ? kids.first : k == "background" ? kids.last : nil
    func through(_ a: Character, _ s: inout _CSSAxis) {
      if k == "overlay" || k == "background" {
        if let p = primary?.axis(a) { s.fill = p.fill; s.rigid = p.rigid; s.fixed = p.fixed; s.soft = p.soft }
        return
      }
      if k == "hstack" || k == "vstack" {
        let main = (k == "hstack") == (a == "x")
        // A soft fill does not grow the stack along its axis.
        let filling = kids.filter { kid in
          let ka = kid.axis(a)
          return ka.fill && (main || kid.kind != "spacer") && !(main && (ka.capIdeal != nil || ka.capContent) && kids.count > 1) && !(main && ka.soft)
        }
        s.fill = !filling.isEmpty
        s.soft = s.fill && filling.allSatisfy { $0.axis(a).soft }
        s.rigid = !kids.isEmpty && kids.allSatisfy { $0.axis(a).rigid } && !s.fill
        return
      }
      s.fill = kids.contains { $0.axis(a).fill }
      s.soft = s.fill && kids.allSatisfy { !$0.axis(a).fill || $0.axis(a).soft }
      s.rigid = !kids.isEmpty && kids.allSatisfy { $0.axis(a).rigid }
    }
    switch k {
    case "intrinsic":
      let text = n.attr("data-layout-leaf") == "text" || e.hasClass("rich-text-run")
      x.rigid = !text; y.rigid = true
      // A Divider is a point thick (the stylesheet's border) and as long as the stack it is in: it takes the whole length across it.
      if n.isDivider {
        if n.vertical { y.fill = true; y.rigid = false; x.fixed = 1; x.rigid = true } else { x.fill = true; x.rigid = false; y.fixed = 1; y.rigid = true }
      }
    case "opaque":
      let type = e.attr("type") ?? ""
      let t = e.tag == "textarea" || (e.tag == "input" && ["text", "search", "email", "password", "url", "tel", "number", ""].contains(type))
      // A composite leaf (a List row's link, a list, a table, a segmented picker) takes the finite width it is offered;
      // a native control and a span (measured as text) keep their ideal width.
      // A `Link` (`a.anchor-link`, inline) is measured as its text: as wide as its label, which wraps where it must.
      let link = e.hasClass("anchor-link")
      let composite = (!["button", "input", "textarea", "select", "label", "details", "span"].contains(e.tag) && !link) || e.hasClass("picker-control") || e.hasClass("disclosure-group")
      let label = (e.tag == "button" || link) && !_cssBlank(e.textContent)
      // A menu Picker shrinks to its arrows in a row too narrow for it (Apple's x-picker-row-tight), as the host measures it.
      let menu = e.tag == "select"
      // Offered no width (along a horizontal ScrollView), a composite leaf keeps its ideal width.
      x.fill = t || composite; x.soft = composite && !t; x.rigid = !t && !label && !menu; y.rigid = true
      // A TextEditor is flexible both ways: it takes the height of its frame, where it holds its text when the frame is smaller.
      if e.tag == "textarea" { y.fill = true; y.rigid = false }
      // A user-defined Layout is as large as Swift's `sizeThatFits` answered for the proposal the page reported.
    case "field":
      x.fill = true; y.rigid = true
      // The browser gives a progress bar no height of its own: it is as tall as its track.
      if e.tag == "progress" { y.fixed = _cssProgressTrack }
    case "flexible": x.fill = true; y.fill = true
    case "spacer":
      x.fill = true; y.fill = true
      let min = _cssNum(n.attr("data-spacer-min"), 8); x.min = min; y.min = min
    case "size":
      x.fixed = _cssNum(n.attr("data-size-w"), 0); y.fixed = _cssNum(n.attr("data-size-h"), 0); x.rigid = true; y.rigid = true
    case "geometry", "panel", "navstack": x.fill = true; y.fill = true
    // Along an axis it scrolls a ScrollView takes its proposal; across, it is as large as its content.
    case "scroll":
      let h = e.hasClass("scroll-horizontal") || e.hasClass("scroll-both"), v = e.hasClass("scroll-vertical") || e.hasClass("scroll-both") || !h
      through("x", &x); through("y", &y)
      if h { x.fill = true; x.soft = false; x.rigid = false }
      if v { y.fill = true; y.soft = false; y.rigid = false }
    // A LabeledContent row is as wide as it is offered, its ideal width offered nothing; as tall as its taller cell.
    case "labeledrow": x.fill = true; x.capContent = true; y.rigid = true
    // `.position(x:y:)` takes its proposal (10 pt where there is none). Among a stack's views, the stack offers it at most
    // what it answers an unlimited proposal: those 10 pt.
    case "position": x.fill = true; y.fill = true; x.capIdeal = 10; y.capIdeal = 10
    case "grid": x.fill = true
    case "table": x.fill = n.colFill.contains(true) || kids.contains { $0.kind != "gridrow" && $0.x.fill && !$0.x.soft }
    case "gridrow", "padding": through("x", &x); through("y", &y)
    case "inset":
      if kids.count < 2 { through("x", &x); through("y", &y); break }
      // The safe-inset rule: the content takes what the inset leaves along its edge; across it, the larger of the two.
      let body = kids[0], inset = kids[1]
      func along(_ s: inout _CSSAxis, _ a: Character) {
        let b = body.axis(a)
        s.fill = b.fill; s.soft = b.fill && b.soft; s.rigid = b.rigid && inset.axis(a).rigid
      }
      func across(_ s: inout _CSSAxis, _ a: Character) {
        let b = body.axis(a), i = inset.axis(a)
        s.fill = b.fill || i.fill; s.soft = s.fill && (!b.fill || b.soft) && (!i.fill || i.soft); s.rigid = b.rigid && i.rigid
      }
      if _cssInsetEdge(n).vertical { along(&y, "y"); across(&x, "x") } else { along(&x, "x"); across(&y, "y") }
    case "aspect":
      x.fill = true; y.fill = false; y.rigid = false
      if let only = kids.first, let fixed = only.x.fixed { x.capIdeal = fixed }
    case "fixed":
      through("x", &x); through("y", &y)
      if n.attr("data-fixed-x") != "false" { x.fill = false; x.soft = false; x.rigid = true; x.ideal = true }
      if n.attr("data-fixed-y") != "false" { y.fill = false; y.soft = false; y.rigid = true; y.ideal = true }
    case "frame":
      through("x", &x); through("y", &y)
      func frame(_ s: inout _CSSAxis, _ w: String, _ mn: String, _ mx: String) {
        let fixed = _cssNum(n.attr("data-frame-" + w)), min = _cssNum(n.attr("data-frame-" + mn)), max = _cssNum(n.attr("data-frame-" + mx))
        if let fixed { s.fixed = fixed; s.fill = false; s.soft = false; s.rigid = true }
        else {
          s.min = min; s.max = max
          if max == .infinity { s.fill = true; s.soft = false; s.rigid = false }
          else if let max { s.fill = false; s.soft = false; s.rigid = false; s.cap = max }
          else if min != nil { s.rigid = false }
        }
      }
      frame(&x, "w", "min-w", "max-w"); frame(&y, "h", "min-h", "max-h")
    default: through("x", &x); through("y", &y)
    }
    n.x = x; n.y = y
  }

  // MARK: chainPlan

  private enum _Entry { case fit(align: Double), fixed(size: Double, align: Double), fill(min: Double?, align: Double), range(min: Double?, max: Double?, align: Double), group(align: Double)
    var isFill: Bool { if case .fill = self { return true }; return false }
    var align: Double {
      switch self { case .fit(let a), .fixed(_, let a), .fill(_, let a), .range(_, _, let a), .group(let a): return a }
    }
    var minimum: Double? {
      switch self { case .fill(let m, _), .range(let m, _, _): return m; default: return nil }
    }
  }

  func chainPlan(_ n: _CSSNode) -> _CSSPlan? {
    guard let layers = n.layers, !layers.isEmpty else { return nil }
    var pad = _CSSEdges(), margin = _CSSEdges()
    func add(_ into: inout _CSSEdges, _ node: _CSSNode) {
      into.top += _cssNum(node.attr("data-padding-top"), 0) ?? 0
      into.leading += _cssNum(node.attr("data-padding-leading"), 0) ?? 0
      into.bottom += _cssNum(node.attr("data-padding-bottom"), 0) ?? 0
      into.trailing += _cssNum(node.attr("data-padding-trailing"), 0) ?? 0
    }
    func sized(_ node: _CSSNode, _ a: Character) -> Bool {
      let w = a == "x" ? "w" : "h"
      return node.attr("data-frame-" + w) != nil || node.attr("data-frame-min-" + w) != nil || node.attr("data-frame-max-" + w) != nil
    }
    let several = n.kids.count > 1
    var boxes: [_CSSNode] = []
    var innerPadding = false
    if n.kind == "padding" { add(&pad, n) }
    for (j, node) in layers.enumerated() {
      let last = j == layers.count - 1
      if node.kind == "padding" { if !boxes.isEmpty { add(&margin, node); innerPadding = true } else { add(&pad, node) }; continue }
      if innerPadding { return nil }
      if node.kind == "frame" && !sized(node, "x") && !sized(node, "y") && !(last && several) { continue }
      boxes.append(node)
    }
    if innerPadding && several { return nil }
    let innermost = layers[layers.count - 1]
    if pad.top < 0 { margin.top += pad.top; pad.top = 0 }
    if pad.leading < 0 { margin.leading += pad.leading; pad.leading = 0 }
    if pad.bottom < 0 { margin.bottom += pad.bottom; pad.bottom = 0 }
    if pad.trailing < 0 { margin.trailing += pad.trailing; pad.trailing = 0 }
    func axisPlan(_ a: Character) -> _CSSAxisPlan? {
      let W = a == "x" ? "w" : "h"
      let outer = n.kind == "frame" ? (a == "x" ? n.ax : n.ay) : 0.5
      var entries: [_Entry] = []
      for node in boxes {
        let al = a == "x" ? node.ax : node.ay
        if node.kind == "fixed" { if node.attr("data-fixed-" + String(a)) != "false" { entries.append(.fit(align: 0.5)) }; continue }
        let fixed = _cssNum(node.attr("data-frame-" + W)), min = _cssNum(node.attr("data-frame-min-" + W)), max = _cssNum(node.attr("data-frame-max-" + W))
        if let fixed { entries.append(.fixed(size: fixed, align: al)) }
        else if max == .infinity { entries.append(.fill(min: min, align: al)) }
        else if min != nil || max != nil { entries.append(.range(min: min, max: max, align: al)) }
        else if node === innermost && several { entries.append(.group(align: al)) }
      }
      if several && innermost.kind == "padding" && !entries.contains(where: { !$0.isFill }) { entries.append(.group(align: 0.5)) }
      // A frame with a minimum and no maximum around a box is as large as the box and at least its minimum: like a filling
      // frame with a minimum, it keeps the element at least that large and aligns the box.
      func floor(_ j: Int) -> Bool {
        if case .range(_, let max, _) = entries[j], max == nil { return entries[(j + 1)...].contains { !$0.isFill } }
        return false
      }
      let boxed = entries.indices.filter { !entries[$0].isFill && !floor($0) }
      if boxed.count > 1 { return nil }
      var track = "minmax(0,1fr)", content = outer, item = outer, least = 0.0
      var range: _CSSRange?
      let fit = entries.contains { if case .fit = $0 { return true }; return false }
      let inset = a == "x" ? pad.leading + pad.trailing : pad.top + pad.bottom
      if boxed.isEmpty {
        if let last = entries.last {
          item = last.align
          let min = Swift.max(0, entries.map { $0.minimum ?? 0 }.max() ?? 0)
          let fixed = a == "x" ? n.x.fixed : n.y.fixed
          if min != 0, let fixed, min + inset > fixed { return nil }
          if min != 0 { track = "minmax(" + _cssVpx(min) + ",1fr)" }
        }
      } else {
        let k = boxed[0], box = entries[k]
        let after = Array(entries[(k + 1)...])
        if k > 0 { content = entries[k - 1].align }
        least = Swift.max(0, entries[..<k].map { $0.minimum ?? 0 }.max() ?? 0)
        item = after.last?.align ?? box.align
        switch box {
        case .fixed(let size, _): track = _cssVpx(size)
        case .fit: track = "max-content"
        case .group: track = n.kids.contains { $0.axis(a).fill } ? "minmax(0,1fr)" : "fit-content(100%)"
        case .range(let min, let max, _): range = _CSSRange(min: min ?? 0, max: max != nil && max != .infinity ? max : nil, filled: !after.isEmpty)
        case .fill: break
        }
      }
      return _CSSAxisPlan(track: track, content: content, item: item, range: range, fit: fit, least: least != 0 ? least + inset : 0)
    }
    guard let px = axisPlan("x"), let py = axisPlan("y") else { return nil }
    return _CSSPlan(pad: pad, margin: margin, x: px, y: py)
  }

  // MARK: declarations

  /// The declaration block of `n` as a child of `parent` (`declarations` of the JS mapper), without `!important`.
  func declarations(_ n: _CSSNode, _ parent: _CSSNode?, rootProposal: _CSSRootProposal?) -> [String] {
    let e = n.element, k = n.kind
    var d: [String] = []
    func push(_ p: String, _ v: String) { d.append(p + ":" + v) }
    let ctx = parent == nil ? "root" : parent!.kind == "hstack" ? "row" : parent!.kind == "vstack" ? "column" : "cell"
    let stack = k == "hstack" || k == "vstack"
    if stack {
      push("display", "flex"); push("flex-direction", k == "hstack" ? "row" : "column"); push("gap", _cssPx(n.spacing))
      push("align-items", "flex-start"); push("justify-content", "flex-start")
    } else if let plan = n.plan {
      func track(_ a: Character) -> String {
        let ap = a == "x" ? plan.x : plan.y
        guard let range = ap.range else { return ap.track }
        let ideal = a == "x" ? n.x.ideal : n.y.ideal
        let offered = (a == "x" ? n.defX : n.defY) && !ap.fit && !(k == "fixed" && ideal)
        if offered { return "minmax(" + _cssVpx(range.min) + "," + (range.max.map(_cssVpx) ?? "1fr") + ")" }
        if let max = range.max { return "fit-content(" + _cssVpx(max) + ")" }
        // Offered nothing, a frame with a minimum is as large as what it holds and at least its minimum.
        return range.min > 0 ? "minmax(" + _cssVpx(range.min) + ",auto)" : "auto"
      }
      push("display", "grid"); push("grid-template-columns", track("x")); push("grid-template-rows", track("y"))
      push("justify-content", _cssGrid[_cssSide(plan.x.content)]); push("align-content", _cssGrid[_cssSide(plan.y.content)])
    } else if k == "navstack" {
      let columns = _cssBarColumns(n)
      push("display", "grid"); push("grid-template-columns", columns ?? "minmax(0,1fr)"); push("grid-template-rows", (n.defY ? "auto minmax(0,1fr)" : "auto auto") + (n.kids.contains { _cssIsBottomBar($0.element) } ? " auto" : ""))
      // Items on one side are 8 px apart; principal items touch, as on the host.
      if columns != nil && _cssShownOn(n, "center").count < 2 { push("column-gap", "8px") }
    } else if k == "labeledrow" {
      // SwiftUI's labeled row (`labeledrow` of the JS mapper): too narrow for both, each column gets an equal share up to
      // its natural width, so a long value wraps beside a short label; with room to spare, label leading, value trailing.
      push("display", "grid"); push("grid-template-columns", "auto auto"); push("justify-content", "space-between"); push("grid-template-rows", "auto")
      push("column-gap", _cssPx(n.spacing)); push("align-items", "center")
    } else if k == "inset" && n.kids.count > 1 {
      // A track for the inset, as large as it is, and one for the content, which takes what is left when there is a
      // proposal along the edge; `spacing` between them.
      let (vertical, start) = _cssInsetEdge(n)
      let body = (vertical ? n.defY : n.defX) ? "minmax(0,1fr)" : "auto"
      let tracks = start ? "auto " + body : body + " auto"
      push("display", "grid")
      if vertical { push("grid-template-columns", "minmax(0,1fr)"); push("grid-template-rows", tracks); push("row-gap", _cssPx(n.spacing)) }
      else { push("grid-template-columns", tracks); push("grid-template-rows", "minmax(0,1fr)"); push("column-gap", _cssPx(n.spacing)) }
    } else if ["zstack", "frame", "padding", "fixed", "aspect", "geometry", "overlay", "background", "scroll", "panel", "tabview", "inset"].contains(k) {
      push("display", "grid"); push("grid-template-columns", "minmax(0,1fr)")
      // A ScrollView holding several views stacks them from the top, leading, with no spacing (the host's `@group`).
      if k == "scroll" && n.kids.count > 1 { push("grid-template-rows", "none"); push("grid-auto-rows", "max-content"); push("align-content", "start") }
      else { push("grid-template-rows", "minmax(0,1fr)") }
      // A GeometryReader is as large as it is proposed, never as its content.
      if k == "geometry" { push("place-items", "start"); push("contain", "size") }
    } else if k == "grid" {
      grid(n, &d)
    } else if k == "table" {
      push("display", "grid")
      push("grid-template-columns", n.cols > 0 ? (0..<n.cols).map { n.colFill[$0] ? "minmax(max-content,1fr)" : "minmax(0,max-content)" }.joined(separator: " ") : "minmax(0,max-content)")
      push("column-gap", _cssPx(n.spacing)); push("row-gap", _cssPx(_cssNum(e.attr("data-row-spacing"), 8) ?? 8)); push("align-content", "start")
    } else if k == "gridrow" {
      push("display", "contents"); return d
    } else if k == "intrinsic" {
      if (e.inlineDisplay ?? "").isEmpty { push("display", "block") }
      if e.tag == "select" || e.hasDescendant(tags: ["select"]) { push("field-sizing", "content") }
      // A vertical Divider draws its line along its leading edge, the stylesheet's rule along the top of a horizontal one.
      if n.isDivider && n.vertical { push("border-top-width", "0"); push("border-left-width", "1px") }
    } else if k == "spacer" || k == "size" || (k == "flexible" && e.children.isEmpty) {
      // A flexible leaf that holds elements keeps the stylesheet's display, which lays them out (NavigationSplitView's
      // grid of columns).
      push("display", "block")
    } else if k == "opaque" && (e.tag == "select" || e.hasDescendant(tags: ["select"])) {
      push("field-sizing", "content")
    } else if k == "field" && e.hasClass("gauge-meter") {
      // A Gauge's label is as wide as its text (the stylesheet's column would stretch it over the track); the track still takes the width.
      push("align-items", "flex-start")
    }
    if k == "tabview" {
      push("padding", "0 0 var(--tab-bottom-inset) 0"); push("padding-inline-start", "var(--tab-sidebar-width)")
    } else if let plan = n.plan {
      let p = plan.pad
      push("padding", _cssPx(p.top) + " " + _cssPx(p.trailing) + " " + _cssPx(p.bottom) + " " + _cssPx(p.leading))
    } else if k == "padding" || k == "labeledrow" {
      func p(_ side: String) -> Double { Swift.max(0, _cssNum(e.attr("data-padding-" + side), 0) ?? 0) }
      push("padding", _cssPx(p("top")) + " " + _cssPx(p("trailing")) + " " + _cssPx(p("bottom")) + " " + _cssPx(p("leading")))
    } else if !_cssLeaves.contains(k) && (k != "grid" || (n.extent.0 == 0 && n.extent.1 == 0)) {
      push("padding", "0")
    }
    push("box-sizing", "border-box")
    if let parent {
      let m = parent.margin
      push("position", "relative"); push("inset", "auto")
      push("margin", m.map { _cssPx($0.top) + " " + _cssPx($0.trailing) + " " + _cssPx($0.bottom) + " " + _cssPx($0.leading) } ?? "0")
      let stackedScroll = parent.kind == "scroll" && parent.kids.count > 1
      push("grid-area", parent.kind == "inset" && parent.kids.count > 1 ? _cssInsetArea(parent, n) : parent.kind == "navstack" ? (_cssIsBottomBar(n.element) ? "3 / 1 / 4 / -1" : _cssBarColumns(parent) != nil ? "2 / 1 / 3 / -1" : "2 / 1") : ctx == "cell" && !["grid", "table", "gridrow"].contains(parent.kind) && !stackedScroll ? "1 / 1" : "auto")
      placement(n, parent, ctx, &d)
    } else if let rootProposal {
      rootPlacement(n, rootProposal, &d)
    } else {
      if let f = n.x.fixed { push("width", _cssVpx(f)) }
      if let f = n.y.fixed { push("height", _cssVpx(f)) }
    }
    if let plan = n.plan {
      if plan.x.least != 0 { push("min-width", _cssVpx(plan.x.least)) }
      if plan.y.least != 0 { push("min-height", _cssVpx(plan.y.least)) }
    }
    if k == "fixed" {
      if n.x.ideal { push("width", "max-content") }
      if n.y.ideal { push("height", "max-content") }
    }
    if k == "aspect" && n.defX, let r = _cssNum(e.attr("data-aspect-ratio")), r != 0 {
      push("aspect-ratio", _cssJS(r)); push("width", "100%"); push("height", "auto")
      if let cap = n.cap { push("max-width", _cssVpx(cap * r)) }
    }
    // A custom SF Symbol is an empty span whose size its Swift view authored (in em), as the host measures it.
    if k == "intrinsic" && e.hasClass("custom-symbol") {
      if let w = e.inlineWidth, !w.isEmpty { push("width", w) }
      if let h = e.inlineHeight, !h.isEmpty { push("height", h) }
    }
    return d
  }

  func grid(_ n: _CSSNode, _ d: inout [String]) {
    let e = n.element, horizontal = e.hasClass("hgrid"), tracks = n.tracks
    func push(_ p: String, _ v: String) { d.append(p + ":" + v) }
    let cols = tracks.map { t -> String in t.type == "fixed" ? _cssPx(t.min) : "minmax(" + _cssPx(t.min) + "," + (t.max == .infinity ? "1fr" : _cssPx(t.max)) + ")" }
    push("display", "grid")
    let rowGap = _cssNum(e.attr("data-row-spacing"), n.spacing) ?? n.spacing
    if let adaptive = tracks.first(where: { $0.type == "adaptive" }) {
      push(horizontal ? "grid-template-rows" : "grid-template-columns", "repeat(auto-fill,minmax(" + _cssPx(adaptive.min) + "," + (adaptive.max == .infinity ? "1fr" : _cssPx(adaptive.max)) + "))")
    } else {
      push(horizontal ? "grid-template-rows" : "grid-template-columns", cols.joined(separator: " "))
    }
    push(horizontal ? "grid-template-columns" : "grid-template-rows", "none")
    push("grid-auto-flow", horizontal ? "column" : "row")
    push("column-gap", _cssPx(tracks.first?.spacing ?? n.spacing)); push("row-gap", _cssPx(rowGap))
    push("justify-items", "start"); push("align-items", "start"); push("align-content", "start")
    func extent(_ which: String) -> Double {
      guard let el = e.children.first(where: { $0.attr("data-lazy-spacer") == which }) else { return 0 }
      return _cssNum(el.attr(horizontal ? "data-size-w" : "data-size-h"), 0) ?? 0
    }
    n.extent = (extent("__lazy_before"), extent("__lazy_after"))
    if n.extent.0 != 0 || n.extent.1 != 0 {
      push("padding", horizontal ? "0 " + _cssVpx(n.extent.1) + " 0 " + _cssVpx(n.extent.0) : _cssVpx(n.extent.0) + " 0 " + _cssVpx(n.extent.1) + " 0")
    }
  }

  // MARK: definite, placement

  /// The height the frames and paddings around an aspect box propose to it, when they propose one (a frame with a fixed height, or a
  /// finite maximum, which SwiftUI proposes to what it holds, so an `.aspectRatio(.fit)` in `.frame(maxHeight: 250)` is at most 250 tall
  /// whatever width it is offered); nil otherwise. The box is then at most that height times its ratio wide (`declarations`).
  /// Only the modifiers that share the element with the box are read (`passHeight` of each, from the outermost in): a stack in
  /// between would share the height among its views.
  func aspectCap(_ n: _CSSNode, _ parent: _CSSNode?) -> Double? {
    guard let parent, n.attr("data-aspect-fill") != "true", (_cssNum(n.attr("data-aspect-ratio")) ?? 0) != 0, let height = parent.heightOut, height < .infinity else { return nil }
    return Swift.max(0, height)
  }

  /// What the modifier `m` proposes to its child as a height, when `height` is proposed to it (nil: it is not a modifier).
  func passHeight(_ m: _CSSNode, _ height: Double) -> Double? {
    var height = height
    switch m.kind {
    case "frame":
      if let fixed = _cssNum(m.attr("data-frame-h")) { return fixed }
      if let max = _cssNum(m.attr("data-frame-max-h")) { height = Swift.min(height, max) }
      if let min = _cssNum(m.attr("data-frame-min-h")) { height = Swift.max(height, min) }
      return height
    case "padding": return height - (_cssNum(m.attr("data-padding-top")) ?? 0) - (_cssNum(m.attr("data-padding-bottom")) ?? 0)
    case "fixed": return m.attr("data-fixed-y") != "false" ? .infinity : height
    default: return nil
    }
  }

  func definite(_ n: _CSSNode, _ parent: _CSSNode?, root: _CSSRootProposal?) -> (Bool, Bool) {
    guard let parent else {
      if let root { return (root.defX, root.defY) }
      return n.kind == "scroll" ? (true, true) : (false, false)
    }
    let px = parent.defX, py = parent.defY, k = parent.kind
    if k == "scroll" {
      let pe = parent.element
      return (px && !(pe.hasClass("scroll-horizontal") || pe.hasClass("scroll-both")), py && !(pe.hasClass("scroll-vertical") || pe.hasClass("scroll-both")))
    }
    // A frame with a minimum proposes at least that minimum where it is proposed nothing.
    if k == "frame" { return (parent.x.fixed != nil || (parent.x.min ?? 0) > 0 || px, parent.y.fixed != nil || (parent.y.min ?? 0) > 0 || py) }
    // A Grid proposes each cell its column's width and its row's height.
    if k == "table" || k == "gridrow" { return (true, true) }
    if k == "fixed" { return (parent.x.ideal ? false : px, parent.y.ideal ? false : py) }
    if k == "geometry" || k == "size" || k == "grid" { return (true, true) }
    if k == "labeledrow" { return (true, false) }
    // An inset is offered its ideal size along its edge; the content, what is left of the proposal.
    if k == "inset" && parent.kids.count > 1 && parent.kids[1] === n { return _cssInsetEdge(parent).vertical ? (px, false) : (false, py) }
    if k == "aspect" { return (px || py, px || py) }
    if (k == "overlay" && parent.kids.first !== n) || (k == "background" && parent.kids.last !== n) { return (true, true) }
    return (px, py)
  }

  private func alignOf(_ a: Double) -> String { _cssFlex[_cssSide(a)] }

  func placement(_ n: _CSSNode, _ parent: _CSSNode, _ ctx: String, _ d: inout [String]) {
    let k = n.kind, e = n.element, ps = parent.kind
    func push(_ p: String, _ v: String) { d.append(p + ":" + v) }
    let stackMain: Character? = ctx == "row" ? "x" : ctx == "column" ? "y" : nil
    func W(_ a: Character) -> String { a == "x" ? "width" : "height" }
    func MIN(_ a: Character) -> String { a == "x" ? "min-width" : "min-height" }
    func MAX(_ a: Character) -> String { a == "x" ? "max-width" : "max-height" }
    func def(_ a: Character) -> Bool { a == "x" ? n.defX : n.defY }
    if ps == "table" && k == "gridrow" { push("display", "contents"); return }
    if ps == "labeledrow" {
      // A cell is as wide as its column and centred in the row.
      push("grid-area", "1 / " + String((parent.kids.firstIndex { $0 === n } ?? 0) + 1)); push("justify-self", "stretch"); push("width", "auto")
      push("min-width", "0"); push("max-width", "none")
      push("align-self", "center"); push("height", "auto"); push("min-height", "0"); push("max-height", "none")
      return
    }
    if ps == "position" {
      // The child of `.position(x:y:)` (`positioned` of the JS mapper): centred on the point, from the leading edge.
      let x = _cssNum(parent.attr("data-position-x"), 0) ?? 0, y = _cssNum(parent.attr("data-position-y"), 0) ?? 0
      push("position", "absolute"); push("inset", "auto"); push("left", _cssVpx(x)); push("top", _cssVpx(y)); push("--sl-px", _cssVpx(x))
      push("translate", "-50% -50%"); push("margin", "0"); push("grid-area", "auto")
      for a in [Character("x"), Character("y")] {
        let s = n.axis(a)
        // Offered the position's whole proposal, a view as large as its content wraps at that size.
        let hugs = s.fixed == nil && !(s.fill && def(a))
        push(MIN(a), s.min.map(_cssVpx) ?? "0")
        push(MAX(a), s.max.flatMap { $0 == .infinity ? nil : _cssVpx($0) } ?? (hugs ? "100%" : "none"))
        push(W(a), s.fixed.map(_cssVpx) ?? (hugs ? "max-content" : "100%"))
      }
      return
    }
    if ps == "table" || ps == "gridrow" {
      let (tax, tay) = parent.hasTableAlign ? parent.tableAlign : (0.5, 0.5)
      let ay = ps == "gridrow" && parent.rowAy != nil ? parent.rowAy! : tay
      let spanning = ps == "table", rows = parent.cols > 0
      // A GridRow's cell, with what the grid cell modifiers say (see the page's mapper, Tools/css-layout.js).
      let cell = ps == "gridrow"
      let anchor = cell ? (e.attr("data-grid-cell-anchor") ?? "").split(separator: ",", omittingEmptySubsequences: false).compactMap { Double($0) } : []
      let anchored = anchor.count == 2 && anchor.allSatisfy { $0.isFinite }
      let unsized = cell ? Int(exactly: _cssNum(e.attr("data-grid-unsized-axes"), 0) ?? 0) ?? 0 : 0
      var columnAlign: Double?
      if cell, n.span == 1, parent.colAlign.indices.contains(n.col), let name = parent.colAlign[n.col] {
        columnAlign = name == "flex-start" ? 0 : name == "center" ? 0.5 : name == "flex-end" ? 1 : nil
      }
      push("grid-column", spanning ? "1 / -1" : cell && n.span > 1 ? "span " + String(n.span) : "auto")
      if (spanning && rows) || unsized & 1 != 0 { push("contain", "inline-size") }
      for (a, al, selfProp) in [(Character("x"), anchored ? anchor[0] : columnAlign ?? tax, "justify-self"), (Character("y"), anchored ? anchor[1] : ay, "align-self")] {
        var sp = n.axis(a)
        if k == "flexible" && !def(a) { sp.fixed = _cssNum(e.attr(a == "x" ? "data-ideal-w" : "data-ideal-h"), 10) }
        push(W(a), "auto"); push(MAX(a), "none"); push(MIN(a), "0")
        if unsized & (a == "x" ? 1 : 2) != 0 {
          push(selfProp, "stretch")
          if a == "x" { if k == "flexible" { push(W(a), "100%") } } else { push(W(a), "0"); push(MIN(a), "100%") }
        } else if let f = sp.fixed { push(W(a), _cssVpx(f)); push(selfProp, alignOf(al)) }
        else if spanning && rows && a == "x" { push(selfProp, "stretch"); if k == "flexible" { push(W(a), "100%") } }
        else if sp.fill && (a == "x" ? true : n.defY) { push(selfProp, "stretch"); if k == "flexible" { push(W(a), "100%") } }
        // An aligned view keeps to its column, except a table (see the page's mapper, Tools/css-layout.js).
        else { push(selfProp, alignOf(al)); if a == "x" && k != "table" { push(MAX(a), "100%") } }
      }
      return
    }
    if ps == "grid" {
      if n.cell < 0 {
        let after = e.attr("data-lazy-spacer") == "__lazy_after"
        push("position", "absolute"); push("width", "0"); push("height", "0"); push("inset", after ? "auto auto 0 0" : "0 auto auto 0")
        push("grid-column", "1 / -1"); push("width", n.x.fixed.map(_cssVpx) ?? "auto"); push("height", n.y.fixed.map(_cssVpx) ?? "auto")
        return
      }
      let t = parent.tracks[n.cell % parent.tracks.count]
      let tax = t.ax ?? parent.ax, tay = t.ay ?? parent.ay
      for (a, al, selfProp) in [(Character("x"), tax, "justify-self"), (Character("y"), tay, "align-self")] {
        let sp = n.axis(a)
        push(W(a), "auto"); push(MAX(a), "none"); push(MIN(a), "0")
        if let f = sp.fixed { push(W(a), _cssVpx(f)); push(selfProp, alignOf(al)) }
        else if sp.fill { push(selfProp, "stretch"); if let m = sp.max, m != .infinity { push(MAX(a), _cssVpx(m)) } }
        else { push(selfProp, alignOf(al)) }
      }
      return
    }
    if (ps == "overlay" && parent.kids.first !== n) || (ps == "background" && parent.kids.last !== n) { layer(n, parent, &d); return }
    // A screen larger than its NavigationStack or tab starts at its top leading corner (`safe`), as on the host.
    let safe = ps == "navstack" || ps == "panel"
    func alignIn(_ a: Double) -> String { safe && _cssSide(a) != 0 ? "safe " + alignOf(a) : alignOf(a) }
    for a in [Character("x"), Character("y")] {
      var s = n.axis(a)
      let w = W(a)
      if (k == "geometry" || k == "position") && !def(a) { s.fixed = 10 }
      if (k == "flexible" || n.isFramedCanvas) && !def(a) && s.fixed == nil { s.fixed = _cssNum(e.attr(a == "x" ? "data-ideal-w" : "data-ideal-h"), 10) }
      // (A Divider across a stack takes the stack's length there, which the stack decides from its other views.)
      if s.fill && !def(a) && !(n.isDivider && stackMain != nil && a != stackMain) { s.fill = false; s.max = nil }
      if k == "spacer", let main = stackMain, a != main { s.fill = false; s.min = nil }
      // Offered nothing, a frame with a finite maximum is as large as what it holds, up to that maximum.
      if s.cap != nil && !def(a) { s.cap = nil; s.hugMax = s.max }
      var place: Double
      if ctx == "cell" { place = a == "x" ? parent.ax : parent.ay }
      else if ctx == "row" { place = a == "y" ? parent.ay : 0 }
      else { place = a == "x" ? parent.ax : 0 }
      // A LabeledContent cell is widened to its column, its content left where it was: at the start.
      if ps == "zstack" && parent.attr("data-cell-kind") == "labeled" { place = 0 }
      if ps == "geometry" || ps == "scroll" { place = 0 }
      // The content starts at the inset's edge's opposite corner; the inset is aligned across its edge.
      if ps == "inset" && parent.kids.count > 1 {
        place = parent.kids[1] === n && a == (_cssInsetEdge(parent).vertical ? "x" : "y") ? (a == "x" ? parent.ax : parent.ay) : 0
      }
      let selfProp = ctx == "cell" ? (a == "x" ? "justify-self" : "align-self") : "align-self"
      let main = a == stackMain
      push(w, "auto"); push(MAX(a), "none")
      if let f = s.fixed {
        push(w, _cssVpx(f))
        if main { push("flex", "0 0 " + _cssVpx(f)) } else { push(selfProp, alignIn(place)) }
        continue
      }
      // A text in a LabeledContent cell keeps its words whole, as the host measures it there (`cellWrap`).
      let keepsWords = k == "intrinsic" && a == "x" && e.insideLabeledCell
      if let m = s.min { push(MIN(a), _cssVpx(m)) } else { push(MIN(a), keepsWords ? "min-content" : "0") }
      if main {
        if k == "spacer" { push("flex", _cssJS(_cssWeight(n.explicitPriority ? n.priority : -1)) + " 1 0%"); continue }
        if s.fill && !s.soft {
          push("flex", _cssJS(_cssWeight(n.priority)) + " 1 0%")
          if let m = s.max, m != .infinity { push(MAX(a), _cssVpx(m)) }
          else if let c = s.capIdeal, parent.kids.count > 1 { push(MAX(a), _cssVpx(c)) }
          else if s.capContent && parent.kids.count > 1 { push(MAX(a), "max-content") }
        // A finite maximum grows from nothing to that maximum, sharing what is left as SwiftUI's stack offers it.
        } else if let c = s.cap { push("flex", _cssJS(_cssWeight(n.priority)) + " 1 0%"); push(MAX(a), _cssVpx(c)) }
        else if s.rigid { push("flex", "0 0 auto") }
        // A <select> grows up to its selected label's width (`sizeSelects`), not to its widest option.
        // Firefox ignores an intrinsic maximum height (`max-height: max-content`), so in a column the share is written
        // with --sl-hug-grow and --sl-hug-basis, which Tools/styles.css sets for Firefox only: there the view keeps its
        // content's height and does not grow (`0 1 auto`).
        else if a == "y" && s.hugMax == nil && e.tag != "select" {
          push("flex", "var(--sl-hug-grow," + _cssJS(_cssWeight(n.priority)) + ") 1 var(--sl-hug-basis,0%)"); push(MAX(a), "max-content")
        }
        else { push("flex", _cssJS(_cssWeight(n.priority)) + " 1 0%"); push(MAX(a), s.hugMax.map(_cssVpx) ?? (e.tag == "select" ? "var(--sl-select-w,max-content)" : "max-content")) }
      } else if let c = s.cap {
        push(w, _cssVpx(c)); push(MAX(a), "100%"); push(selfProp, alignIn(place))
      } else if s.fill {
        let m = parent.margin
        let inset = m == nil ? 0 : a == "x" ? m!.leading + m!.trailing : m!.top + m!.bottom
        if k == "flexible" || k == "opaque" { push(w, inset != 0 ? "calc(100% - " + _cssPx(inset) + ")" : "100%"); push(selfProp, "stretch") }
        // An aspect box capped by the height it is proposed is narrower than its cell: aligned in it, as the frame aligns it.
        else { push(selfProp, n.cap != nil && a == "x" ? alignIn(place) : "stretch") }
      } else {
        push(selfProp, alignIn(place))
        if let m = s.hugMax { push(MAX(a), _cssVpx(m)) }
        // An aligned view keeps to its cell, except a ZStack (see the page's mapper, Tools/css-layout.js).
        else if !s.ideal && def(a) && a == "x" && k != "zstack" { push(MAX(a), "100%") }
        // Along the axis a ScrollView scrolls, its content is as wide as it wants, not squeezed into the viewport.
        else if ps == "scroll" && !def(a) && a == "x" { push(w, "max-content") }
      }
    }
  }

  func rootPlacement(_ n: _CSSNode, _ root: _CSSRootProposal, _ d: inout [String]) {
    func push(_ p: String, _ v: String) { d.append(p + ":" + v) }
    if root.height == "cell" {
      // The container is a one-cell grid (`data-cl-host`): the root fills it or is aligned in it, at the top.
      push("position", "relative"); push("inset", "auto"); push("margin", "0"); push("min-width", "0"); push("min-height", "0")
      push("max-width", "none"); push("max-height", "none")
      for (s, w, selfProp, al) in [(n.x, "width", "justify-self", root.ax), (n.y, "height", "align-self", 0.0)] {
        if let f = s.fixed { push(w, _cssVpx(f)); push(selfProp, _cssFlex[_cssSide(al)]) }
        else if s.fill { push(w, "auto"); push(selfProp, "stretch") }
        // A finite maximum takes min(offered, maximum) whatever the content is, the cell being what is offered.
        else if let c = s.cap, (w == "width" ? root.defX : root.defY) { push(w, _cssVpx(c)); push("max-" + w, "100%"); push(selfProp, _cssFlex[_cssSide(al)]) }
        else { push(w, w == "width" ? "fit-content" : "auto"); push(selfProp, _cssFlex[_cssSide(al)]) }
        if s.fixed == nil, let m = s.min { push("min-" + w, _cssVpx(m)) }
      }
      return
    }
    push("position", "relative"); push("inset", "auto"); push("flex", "none"); push("align-self", "flex-start")
    push("min-width", "0"); push("min-height", "0"); push("max-height", "none")
    if let f = n.x.fixed { push("width", _cssVpx(f)) }
    else if n.x.fill && root.defX { push("width", "100%") }
    else { push("width", "fit-content") }
    push("max-width", n.x.fixed != nil ? "none" : "100%")
    if let f = n.y.fixed { push("height", _cssVpx(f)) }
    else if n.y.fill && root.defY { push("height", root.height) }
    else { push("height", "auto") }
    let fills = n.x.fill && root.defX && n.x.fixed == nil
    push("margin", fills ? "0" : "0 " + (root.ax < 0.75 ? "auto" : "0") + " 0 " + (root.ax > 0.25 ? "auto" : "0"))
  }

  /// `rows` with each flexible track (`1fr`) as tall as its content, or nil when it has none or repeats tracks.
  func contentRows(_ rows: String) -> String? {
    if rows.hasPrefix("grid-template-rows:repeat(") { return nil }
    let chars = Array(rows)
    var out = "", found = false, i = 0
    while i < chars.count {
      if i + 3 <= chars.count, chars[i] == "1", chars[i + 1] == "f", chars[i + 2] == "r" { out += "max-content"; found = true; i += 3 }
      else { out.append(chars[i]); i += 1 }
    }
    return found ? out : nil
  }

  /// A secondary child of an overlay or background (`layer` of the JS mapper).
  func layer(_ n: _CSSNode, _ parent: _CSSNode, _ d: inout [String]) {
    func push(_ p: String, _ v: String) { d.append(p + ":" + v) }
    push("position", "absolute"); push("inset", "0")
    for (a, m1, m2) in [(Character("x"), "margin-left", "margin-right"), (Character("y"), "margin-top", "margin-bottom")] {
      let al = a == "x" ? parent.ax : parent.ay
      let s = n.axis(a)
      if let f = s.fixed { push(a == "x" ? "width" : "height", _cssVpx(f)) }
      else if s.fill || n.kind == "flexible" { push(a == "x" ? "width" : "height", "100%"); continue }
      else {
        // A hugging box has no free space; WebKit measures it from the containing block, so align at the start. WebKit
        // also grows a flexible row to the containing block, so the row is as tall as its content.
        push(a == "x" ? "width" : "height", "fit-content"); push(a == "x" ? "justify-content" : "align-content", "start")
        if a == "y", let rows = d.last(where: { $0.hasPrefix("grid-template-rows:") }), let hugging = contentRows(rows) { d.append(hugging) }
      }
      if s.fill || n.kind == "flexible" { continue }
      push(m1, al > 0.25 ? "auto" : "0"); push(m2, al < 0.75 ? "auto" : "0")
    }
  }

  /// A NavigationStack's bar item (`barItem` of the JS mapper).
  func barItem(_ n: _CSSNode, _ item: _CSSBarItem) -> [String] {
    if !item.shown { return ["display:none"] }
    let e = n.element
    let title = e.has("data-navigation-title") && e.attr("data-navigation-bar-hidden") != "true"
    let large = title && e.attr("data-navigation-title-display-mode") == "large"
    let principals = _cssShownOn(n, "center").count > 1, several = _cssShownOn(n, item.side).count > 1
    var d = ["position:relative", "inset:auto", "grid-area:" + _cssBarArea(n, item), "justify-self:" + item.side, "width:max-content", "max-width:100%", "min-width:0",
             // Principal items touch, so the items on a side are 8 px apart by their margins, not by a gap (on both sides, so that
             // blocks of items as wide as each other leave the group centred on the bar).
             principals ? (item.side == "start" ? "margin:0 8px 0 0" : item.side == "end" && several ? "margin:0 0 0 8px" : "margin:0") : "margin:0", "z-index:20",
             "border-bottom:0", "background:transparent", "-webkit-backdrop-filter:none", "backdrop-filter:none", "transform:none"]
    if large { d += ["align-self:start", "min-height:3rem", "box-sizing:border-box"] }
    else { d.append("align-self:" + (title ? "center" : "start")) }
    return d
  }

  // MARK: assign, run

  /// Every run disables keep placeholders when the set of styled elements changed wholesale (emission turned on or off,
  /// a root released).
  private(set) var forceFull = false
  private var runs = 0
  private var rootsLastRun: Set<ObjectIdentifier> = []
  /// Rules created in this run: a block's id, and whether the rule is the collapsed rail's (`.sr<n>`).
  private var newRules: [(id: Int, rail: Bool)] = []
  /// Blocks already sent as a rail rule.
  private var railRules: Set<Int> = []

  /// The properties each block declares, and the longhands its shorthands cover.
  private var properties: [Set<String>] = [[]]

  private func intern(_ block: String) -> Int {
    if let id = blocks[block] { return id }
    let id = texts.count
    blocks[block] = id
    texts.append(block)
    var declared: Set<String> = []
    for declaration in block.split(separator: ";") {
      guard let colon = declaration.firstIndex(of: ":") else { continue }
      let name = String(declaration[..<colon])
      declared.insert(name)
      for longhand in _cssLonghands[name] ?? [] { declared.insert(longhand) }
    }
    properties.append(declared)
    newRules.append((id: id, rail: false))
    return id
  }

  /// The declarations as one block, each marked `!important`, built in one string (no intermediate string per declaration).
  private func importantBlock(_ declarations: [String]) -> String {
    var out = ""
    out.reserveCapacity(declarations.reduce(0) { $0 + $1.utf8.count + 11 })
    for (index, declaration) in declarations.enumerated() {
      if index > 0 { out += ";" }
      out += declaration
      out += "!important"
    }
    return out
  }

  /// `_cssLengthVariables` of a block, remembered: the blocks of a tree repeat (every row of a list, every cell of a grid
  /// writes the same declarations), so most are split into text and lengths once. Bounded; it starts over past the limit.
  private var lengthVariablesMemo: [String: (text: String, lengths: [String])] = [:]
  private var lengthVariablesMemoLiteral: [String: (text: String, lengths: [String])] = [:]
  private func lengthVariables(_ block: String, variables: Bool) -> (text: String, lengths: [String]) {
    if variables, let hit = lengthVariablesMemo[block] { return hit }
    if !variables, let hit = lengthVariablesMemoLiteral[block] { return hit }
    let result = _cssLengthVariables(block, variables: variables)
    if lengthVariablesMemo.count + lengthVariablesMemoLiteral.count >= 4096 { lengthVariablesMemo = [:]; lengthVariablesMemoLiteral = [:] }
    if variables { lengthVariablesMemo[block] = result } else { lengthVariablesMemoLiteral[block] = result }
    return result
  }

  /// Whether the block `id` declares `property` (itself or through a shorthand): the block's `!important` declaration
  /// wins over an inline one, so the publication need not carry the inline value.
  func declares(_ id: Int, _ property: String) -> Bool { id < properties.count && properties[id].contains(property) }

  /// Gives every node below `top` its block (`assign` of the JS mapper); returns whether a block changed below.
  private func assign(_ top: _CSSNode, _ proposal: _CSSRootProposal, rail: Bool = false) {
    var path: [ObjectIdentifier] = []
    func set(_ fiber: Fiber, _ id: Int, _ lengths: [String] = []) {
      let key = ObjectIdentifier(fiber)
      // A new length alone changes the element's inline style, not its rule.
      if (rail ? railAssigned[key] : assigned[key]) != id || (!rail && (assignedLengths[key] ?? []) != lengths) {
        if rail { railAssigned[key] = id } else { assigned[key] = id; assignedLengths[key] = lengths.isEmpty ? nil : lengths }
        changed.insert(key)
        for ancestor in path { changed.insert(ancestor) }
      }
      if rail, !railRules.contains(id) { railRules.insert(id); newRules.append((id: id, rail: true)) }
    }
    // Walked with a stack of its own, not one call per level (see `analyse`): an `exit` step leaves a node's subtree.
    enum Step { case enter(_CSSNode, _CSSNode?, String), exit }
    var steps: [Step] = [.enter(top, nil, "0")]
    while let step = steps.popLast() {
      guard case let .enter(n, parent, flag) = step else { path.removeLast(); continue }
      Self.stackProbe?()
      let (dx, dy) = definite(n, parent, root: parent == nil ? proposal : nil)
      n.defX = dx; n.defY = dy
      let bits = (dx ? "1" : "0") + (dy ? "1" : "0")
      n.cap = n.kind == "aspect" ? aspectCap(n, parent) : nil
      let ctx = (parent.map { $0.ctxKey + "|" + flag + "|" + bits } ?? "root" + bits + "|" + proposal.height + "|" + _cssJS(proposal.ax)) + (n.cap.map { "|c" + _cssJS($0) } ?? "")
      if n.ctxSeen == ctx, n.applied != nil { continue }
      // (A collapsed rail's block keeps its lengths in the text: an element has one set of `--len<i>`, its expanded block's.)
      let (block, lengths) = lengthVariables(importantBlock(declarations(n, parent, rootProposal: parent == nil ? proposal : nil)), variables: !rail)
      let id = intern(block)
      set(n.element.fiber, id, lengths)
      n.applied = id
      n.ctxSeen = ctx
      path.append(ObjectIdentifier(n.element.fiber))
      if n.kind == "navstack" {
        for item in n.bar { set(item.element.fiber, intern(barItem(n, item).map { $0 + "!important" }.joined(separator: ";"))) }
      }
      for hidden in n.railHidden { set(hidden.fiber, intern("display:none!important")) }
      var holder = n
      n.heightOut = passHeight(n, .infinity)
      if n.layers == nil && n.kind == "padding" {
        var m = _CSSEdges()
        m.top = Swift.min(0, _cssNum(n.attr("data-padding-top"), 0) ?? 0)
        m.leading = Swift.min(0, _cssNum(n.attr("data-padding-leading"), 0) ?? 0)
        m.bottom = Swift.min(0, _cssNum(n.attr("data-padding-bottom"), 0) ?? 0)
        m.trailing = Swift.min(0, _cssNum(n.attr("data-padding-trailing"), 0) ?? 0)
        n.margin = m.isZero ? nil : m
      }
      if let layers = n.layers, let plan = n.plan {
        for layer in layers {
          let (lx, ly) = definite(layer, holder, root: nil)
          layer.defX = lx; layer.defY = ly
          layer.heightOut = holder.heightOut.flatMap { passHeight(layer, $0) }
          holder = layer
        }
        holder.ax = plan.x.item; holder.ay = plan.y.item; holder.ctxKey = n.ctxKey + "|in"
        holder.margin = plan.margin.isZero ? nil : plan.margin
      }
      steps.append(.exit)
      let layered = n.kind == "overlay" || n.kind == "background" || n.kind == "grid"
      for (i, kid) in n.kids.enumerated().reversed() {
        let flag: String
        if !layered { flag = "0" }
        else if n.kind == "overlay" { flag = i == 0 ? "true" : "false" }
        else if n.kind == "background" { flag = i == n.kids.count - 1 ? "true" : "false" }
        else { flag = String(i) }
        steps.append(.enter(kid, holder, flag))
      }
    }
  }

  /// The top-level elements of the tree (what `#embedded-app-root` holds), fragments flattened.
  private func topElements(_ fiber: Fiber) -> [_CSSElement] {
    // A loop in document order, as the recursion over fragments was.
    var out: [_CSSElement] = []
    var pending = [fiber]
    while let current = pending.popLast() {
      switch current.renderNode.kind {
      case .element: out.append(_CSSElement(fiber: current, insideTextLeaf: false, insideButton: false, parentTag: "div"))
      case .fragment: pending.append(contentsOf: current.children.reversed())
      default: break
      }
    }
    return out
  }

  /// Analyses and styles the window roots of `tree`, before the snapshot of a publication.
  func run(_ treeRoot: Fiber) {
    changed = []
    forceFull = false
    newRules = []
    runs += 1
    // Lengths that follow a resize are variables, so the blocks of a view tree are as many as its structures; a tree whose paddings or
    // gaps change with every frame could still mint one for each value, and the page keeps every rule it was sent. Past the limit
    // the page's mapper takes over, as it does when the emitter is off.
    guard enabled, texts.count < blockLimit else {
      if !assigned.isEmpty || !railAssigned.isEmpty { assigned = [:]; assignedLengths = [:]; railAssigned = [:]; cache = [:]; railCache = [:]; forceFull = true }
      rootsLastRun = []; roots = []; hosts = []
      return
    }
    var (styled, hostsNow) = styleRoots(treeRoot)
    // A root that CSS laid out last time and does not now (something it cannot express appeared, or it left): its
    // elements lose their blocks, and the page's mapper takes it over.
    if !rootsLastRun.isSubset(of: styled) {
      assigned = [:]; assignedLengths = [:]; railAssigned = [:]; cache = [:]; railCache = [:]; forceFull = true
      (styled, hostsNow) = styleRoots(treeRoot)
    }
    // A content element that becomes, or stops being, a one-cell grid changes its attributes.
    for host in hostsNow.symmetricDifference(hosts) { changed.insert(host) }
    hosts = hostsNow
    rootsLastRun = styled
    roots = styled
    if runs % 64 == 0 { prune(treeRoot) }
  }

  /// Analyses and styles every root CSS can lay out: the window root, the content of each sidebar slot of the tab views
  /// it holds (for the expanded sidebar and for the collapsed rail), and each presentation's content that holds its root
  /// alone. Returns the roots it styled and the presentation contents made one-cell grids.
  private func styleRoots(_ treeRoot: Fiber) -> (Set<ObjectIdentifier>, Set<ObjectIdentifier>) {
    var styled: Set<ObjectIdentifier> = [], hostsNow: Set<ObjectIdentifier> = []
    // Presentations sit where their modifier is (in a `presentation-host`) or at the top; each one's content root may
    // hold more.
    var presentations: [_CSSElement] = []
    for e in topElements(treeRoot) where !e.hasClass("presentation-backdrop") {
      if e.hasClass("presentation-root") { presentations.append(e); continue }
      let node = analyse(e)
      if node.supported {
        assign(node, .window)
        styled.insert(ObjectIdentifier(e.fiber))
      }
      presentations += node.presentations
      // The content of each NavigationSplitView column (the compact back button is the stylesheet's).
      for splitView in node.splitViews {
        for column in splitView.children where column.hasClass("navigation-column") && column.attr("data-column-hidden") != "true" {
          for root in column.children where !root.has("data-compact-back") {
            let columnNode = analyse(root)
            presentations += columnNode.presentations
            guard columnNode.supported else { continue }
            assign(columnNode, .column)
            styled.insert(ObjectIdentifier(root.fiber))
          }
        }
      }
      for tabView in node.tabViews {
        for (placement, root) in _cssSidebarSlotRoots(of: tabView) {
          let expanded = analyse(root)
          analysingRail = true; railHidesStackTail = placement == "bottom-bar"
          let collapsed = analyse(root)
          analysingRail = false; railHidesStackTail = false
          guard expanded.supported && collapsed.supported else { continue }
          assign(expanded, .slot)
          assign(collapsed, .rail, rail: true)
          styled.insert(ObjectIdentifier(root.fiber))
        }
      }
    }
    while let presentation = presentations.popLast() {
      guard let (content, root) = _cssPresentationRoot(in: presentation) else { continue }
      let node = analyse(root)
      presentations += node.presentations
      guard node.supported else { continue }
      assign(node, .presentation)
      styled.insert(ObjectIdentifier(root.fiber)); hostsNow.insert(ObjectIdentifier(content.fiber))
    }
    return (styled, hostsNow)
  }

  /// Forgets the analyses and blocks of fibers that left the tree (walked with a stack of its own, see `analyse`).
  private func prune(_ treeRoot: Fiber) {
    var live: Set<ObjectIdentifier> = []
    var stack = [treeRoot]
    while let fiber = stack.popLast() { live.insert(ObjectIdentifier(fiber)); stack.append(contentsOf: fiber.children) }
    cache = cache.filter { live.contains($0.key) }
    railCache = railCache.filter { live.contains($0.key) }
    assigned = assigned.filter { live.contains($0.key) }
    assignedLengths = assignedLengths.filter { live.contains($0.key) }
    railAssigned = railAssigned.filter { live.contains($0.key) }
  }

  /// The rules the host may not have yet: every rule first published after the epoch it acknowledged (nil once it has
  /// them all; the host takes no layout pass for a change of this attribute alone).
  func rulesAttribute(acked: UInt64) -> String? {
    unacknowledged.removeAll { $0.epoch <= acked }
    guard enabled, !unacknowledged.isEmpty || !newRules.isEmpty else { return nil }
    // `.sl<n>{block}` a line; a collapsed rail's rule is `.sr<n>{block}` (the page scopes it to the rail).
    var out = ""
    for entry in unacknowledged { out += (entry.rail ? ".sr" : ".sl") + String(entry.id) + "{" + texts[entry.id] + "}\n" }
    for rule in newRules { out += (rule.rail ? ".sr" : ".sl") + String(rule.id) + "{" + texts[rule.id] + "}\n" }
    return out
  }

  /// Records the epoch the rules created in this run are published at.
  func published(epoch: UInt64) {
    for rule in newRules { unacknowledged.append((id: rule.id, rail: rule.rail, epoch: epoch)) }
    newRules = []
  }
}
