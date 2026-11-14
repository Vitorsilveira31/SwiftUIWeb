/// SwiftUI hit testing for the DOM. A SwiftUI layout container that paints
/// nothing (a stack, a frame, a spacer, padding) is transparent to touches:
/// the view beneath it in a ZStack, or the backdrop behind a dialog's empty
/// areas, receives them. A DOM element captures pointer events whatever it
/// paints, so the serializer marks such containers `passthrough`
/// and the stylesheet gives them `pointer-events: none` while their children
/// stay interactive (see `Tools/styles.css`).
extension _RenderNode {
  /// Runs `body` on every element this node stands for: itself, or, for a
  /// `Group` fragment that has no DOM host, each of its rendered children.
  /// SwiftUI applies a modifier on a Group to each child, so modifiers that
  /// attach events, hit regions or attributes use this instead of writing
  /// onto a fragment the serializer cannot represent.
  public func _forEachHost(_ body: (_RenderNode) -> Void) {
    guard case .fragment = kind else {
      body(self)
      return
    }
    // A loop over the elements in order, looking through the groups inside this one: groups nest as deep as the view
    // tree does.
    var pending = Array(children.reversed())
    while let node = pending.popLast() {
      if case .fragment = node.kind {
        pending.append(contentsOf: node.children.reversed())
      } else {
        body(node)
      }
    }
  }

  /// Layout wrappers that paint nothing of their own.
  private static let _layoutKinds: Set<String> = [
    "zstack", "vstack", "hstack", "grid", "gridrow", "spacer", "frame", "flexible", "inset", "padding",
    "container-relative", "geometry", "intrinsic", "position", "offset", "fixed", "overlay", "background", "aspect"
  ]
  /// Events the renderer coordinates itself; they never make a node interactive.
  private static let _lifecycleEvents: Set<String> = [
    "appear", "disappear", "task", "geometry", "geometryChange", "openURL", "presentation-dismiss", "web-navigation", "web-external-link"
  ]
  private static let _paintedStylePrefixes = ["background", "border", "box-shadow", "outline", "backdrop-filter", "filter", "mask"]
  private static let _interactiveAttributes = ["data-content-shape", "data-background-style", "tabindex", "role", "contenteditable", "data-press-tracking", "draggable"]

  /// True when this element is a pure layout container: a layout kind that
  /// paints nothing, carries no gesture or focus, and is not a scroll surface.
  public var _isHitTransparent: Bool {
    guard case .element = kind else { return false }
    // Each storage is read once: the serializer asks this of every layout container it writes.
    let attributes = self.attributes
    guard let layout = attributes["data-layout-kind"], Self._layoutKinds.contains(layout) else { return false }
    let events = self.events
    if !events.isEmpty { for name in events.keys where !Self._lifecycleEvents.contains(name) { return false } }
    for name in Self._interactiveAttributes where attributes[name] != nil { return false }
    // Every painted prefix starts with one of four letters, which sorts out nearly all the declarations of a layout
    // container (`display`, `flex`, `padding`...) before any prefix is compared.
    for (key, _) in styles {
      guard let first = key.utf8.first, first == UInt8(ascii: "b") || first == UInt8(ascii: "o") || first == UInt8(ascii: "f") || first == UInt8(ascii: "m") else { continue }
      if Self._paintedStylePrefixes.contains(where: { key.hasPrefix($0) }) { return false }
    }
    for name in classes where name == "scroll-view" || name == "tab-view" { return false }
    return true
  }
}
