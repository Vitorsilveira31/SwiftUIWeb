// Non-generic builders for the `View` modifiers declared in Compatibility.swift.
// The generic methods only wrap the result with `modifier(_xxxModifier(...))`;
// building the style/attribute tables here compiles them once instead of once
// per view type the modifier is applied to.

// Same formatting as the private `clean` in the source file these builders belong to.
// Int64(exactly:) is nil, not a trap, for a whole value Int64 cannot hold (`.opacity(1e300)`).
private extension Double { var clean: String { Int64(exactly: self).map { String($0) } ?? String(self) } }

@inline(never)
package func _shadowModifier(color: Color, radius: Double, x: Double, y: Double) -> _SemanticCompatibilityModifier {
  let blur = (radius * 2).clean
  return _SemanticCompatibilityModifier(styles: ["box-shadow": "\(x.clean)px \(y.clean)px \(blur)px \(color.cssValue)"])
}

@inline(never)
func _trackingModifier(_ value: Double) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: ["letter-spacing": "\(value.clean)px"])
}

@inline(never)
package func _kerningModifier(_ value: Double) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: ["letter-spacing": "\(value.clean)px"])
}

@inline(never)
package func _baselineOffsetModifier(_ value: Double) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: ["vertical-align": "\(value.clean)px"])
}

@inline(never)
package func _lineSpacingModifier(_ value: Double) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: ["line-height": "calc(1.2em + \(value.clean)px)"])
}

@inline(never)
package func _defaultScrollAnchorModifier(_ anchor: UnitPoint) -> _SemanticCompatibilityModifier {
  let value = "\(anchor.x.clean),\(anchor.y.clean)"
  return _SemanticCompatibilityModifier(attributes: ["data-default-scroll-anchor": value, "data-scroll-position-initial-anchor": value])
}

@inline(never)
func _blurModifier(radius: Double) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-blur": String(radius)], styles: ["filter": "blur(\(radius.clean)px)"])
}

/// The `padding-*` declarations for the selected edges, all with the same length.
private func uniformPadding(_ edges: Edge.Set, _ value: String) -> _NodeValues {
  var styles = _NodeValues()
  if edges.contains(.top) { styles["padding-top"] = value }
  if edges.contains(.leading) { styles["padding-left"] = value }
  if edges.contains(.bottom) { styles["padding-bottom"] = value }
  if edges.contains(.trailing) { styles["padding-right"] = value }
  return styles
}

@inline(never)
func _contentMarginsModifier(_ edges: Edge.Set, _ length: Double?) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: uniformPadding(edges, "\((length ?? 16).clean)px"))
}

@inline(never)
package func _contentMarginsModifier(_ edges: Edge.Set, _ length: Double?, for placement: ContentMarginPlacement) -> _SemanticCompatibilityModifier {
  let amount = length ?? 16
  let insets = "\(edges.contains(.top) ? amount : 0),\(edges.contains(.leading) ? amount : 0),\(edges.contains(.bottom) ? amount : 0),\(edges.contains(.trailing) ? amount : 0)"
  return _SemanticCompatibilityModifier(attributes: ["data-content-margins-placement": placement.rawValue, "data-scroll-content-margins": insets], styles: uniformPadding(edges, "\(amount.clean)px"))
}

@inline(never)
package func _contentMarginsModifier(_ edges: Edge.Set, _ insets: EdgeInsets, for placement: ContentMarginPlacement) -> _SemanticCompatibilityModifier {
  var styles = _NodeValues()
  if edges.contains(.top) { styles["padding-top"] = "\(insets.top.clean)px" }
  if edges.contains(.leading) { styles["padding-left"] = "\(insets.leading.clean)px" }
  if edges.contains(.bottom) { styles["padding-bottom"] = "\(insets.bottom.clean)px" }
  if edges.contains(.trailing) { styles["padding-right"] = "\(insets.trailing.clean)px" }
  let margins = "\(insets.top),\(insets.leading),\(insets.bottom),\(insets.trailing)"
  return _SemanticCompatibilityModifier(attributes: ["data-content-margins-placement": placement.rawValue, "data-scroll-content-margins": margins], styles: styles)
}

@inline(never)
func _resizableModifier(capInsets: EdgeInsets, resizingMode: Image.ResizingMode) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-resizable": "true", "data-resizing-mode": resizingMode.rawValue], styles: ["object-fit": "contain", "object-position": "center"])
}

@inline(never)
package func _italicModifier(_ active: Bool) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: ["font-style": active ? "italic" : "normal"])
}

/// `toolbar(_:for:)` records one attribute per placement, so several modifiers on one view merge as they do in
/// SwiftUI: each placement keeps its own last declaration, and a placement never overwrites another.
@inline(never)
package func _toolbarModifier(_ visibility: Visibility, for bars: [ToolbarPlacement]) -> _SemanticCompatibilityModifier {
  var attributes: _NodeValues = [:]
  for bar in bars {
    attributes[_toolbarVisibilityAttribute(bar)] = visibility.rawValue
    if case .tabBar = bar, visibility == .hidden { _TabBarHiding.requested = true }
  }
  return _SemanticCompatibilityModifier(attributes: attributes)
}

/// The attribute that holds the visibility of one bar, for example `data-toolbar-visibility-navigationbar`.
/// The name is lowercase because HTML attribute names are case-insensitive in the browser.
func _toolbarVisibilityAttribute(_ bar: ToolbarPlacement) -> String {
  switch bar {
  case .automatic: "data-toolbar-visibility-automatic"
  case .navigationBar: "data-toolbar-visibility-navigationbar"
  case .tabBar: "data-toolbar-visibility-tabbar"
  case .bottomBar: "data-toolbar-visibility-bottombar"
  case .windowToolbar: "data-toolbar-visibility-windowtoolbar"
  }
}

@inline(never)
package func _transformEffectModifier(_ transform: CGAffineTransform) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: [
      "transform": "matrix(\(Double(transform.a).clean), \(Double(transform.b).clean), \(Double(transform.c).clean), \(Double(transform.d).clean), \(Double(transform.tx).clean), \(Double(transform.ty).clean))"
    ])
}

// Modifiers whose tables do not depend on an argument. A function, not a `static let`: a global would
// add a lazy initializer per modifier, which costs more code than it saves in Embedded Swift.

@inline(never)
package func _buttonBorderShapeModifier(_ shape: ButtonBorderShape) -> _SemanticCompatibilityModifier {
  let value: String
  switch shape { case .automatic: value = "automatic"; case .capsule: value = "capsule"; case .circle: value = "circle"; case .roundedRectangle(let radius): value = "rounded-\(radius.clean)" }
  // The bordered chrome and its highlight take this shape; `automatic` keeps the style's own corners.
  var attributes: _NodeValues = ["data-button-border-shape": value]
  var styles: _NodeValues = [:]
  switch shape {
  case .automatic: break
  case .capsule, .circle:
    styles["border-radius"] = "9999px"
    attributes["data-visible-shape"] = "true"
  case .roundedRectangle(let radius):
    styles["border-radius"] = "\(max(0, radius).clean)px"
    attributes["data-visible-shape"] = "true"
  }
  if let radius = styles["border-radius"] { styles["--shape-clip"] = "inset(0 round \(radius))" }
  return _SemanticCompatibilityModifier(attributes: attributes, styles: styles)
}

