// SwiftUI draws a button's pressed and focus feedback, and its hit area, from
// the button's shape: a `contentShape`, the `buttonBorderShape` of a bordered
// style, or else the visible shape of its label. A web `<button>` is always a
// rectangle, so `Button` copies that corner radius onto its element. The
// element's background, focus ring and hit testing then follow the shape, and a
// control with no declared shape keeps the plain rectangle with no fill of its own.
//
// Priority: a `contentShape` on the label, then the first shape painted or
// clipped by the label's background, overlay or frame wrappers. Layout
// containers are not searched, so an icon inside a row does not shape the row.

/// Applies the label's visible corner radius to the `<button>` element.
///
/// The element's hit layer is clipped to the same radius (`--shape-clip`):
/// browsers do not hit-test a pseudo-element's corners from `border-radius`
/// alone, but they do from a clip path.
@MainActor package func _applyButtonVisibleShape(_ label: _RenderNode, to control: _RenderNode) {
  guard let corners = _labelVisibleCornerStyles(label, depth: 0) else { return }
  for (property, value) in corners { control.styles[property] = value }
  if let radius = corners["border-radius"] { control.styles["--shape-clip"] = "inset(0 round \(radius))" }
  control.attributes["data-visible-shape"] = "true"
}

/// The corner declarations of the first visible shape found, or nil when the
/// label has no declared shape. A logical per-corner shape (`UnevenRoundedRectangle`)
/// keeps its own logical properties, so its corners follow layout direction. Such a
/// shape sets no `--shape-clip`, so its hit layer stays the full box: a known gap.
@MainActor private func _labelVisibleCornerStyles(_ node: _RenderNode, depth: Int) -> _NodeValues? {
  if node.attributes["data-content-shape"] != nil {
    let corners = _cornerStyles(of: node)
    if !corners.isEmpty { return corners }
    switch node.attributes["data-content-shape"] {
    case "circle", "capsule": return ["border-radius": "9999px"]
    case "rectangle": return ["border-radius": "0px"]
    default: return nil
    }
  }
  let corners = _cornerStyles(of: node)
  if !corners.isEmpty, node.attributes["data-shape-geometry"] == "css-radius" || node.styles["overflow"] == "hidden" {
    return corners
  }
  // A circle is painted as an SVG path, not as CSS corners. In a square box a
  // 9999px radius is exactly that circle, so the button takes the same shape.
  if node.attributes["data-shape"] == "circle" { return ["border-radius": "9999px"] }
  // One element can stand for a chain of layout wrappers (`_SemanticLayers`); the search went through each of them as it
  // went through a wrapper element, and stopped at the first that is not a frame.
  let chain = _SemanticLayers.innerLayers(of: node).isEmpty ? [] : _SemanticLayers.layers(of: node)
  let steps = max(1, chain.count)
  guard depth + steps - 1 < 4, _isVisibleShapeWrapper(node), chain.allSatisfy({ $0.kind == "frame" }) else { return nil }
  for child in node.children {
    if let corners = _labelVisibleCornerStyles(child, depth: depth + steps) { return corners }
  }
  return nil
}

/// Background, overlay and frame wrappers carry the shape of their label; their
/// content is only searched through these wrappers.
@MainActor private func _isVisibleShapeWrapper(_ node: _RenderNode) -> Bool {
  node.classes.contains("backdrop-layer") ||
    node.classes.contains("overlay-layer") ||
    node.classes.contains("frame-box")
}

@MainActor private func _cornerStyles(of node: _RenderNode) -> _NodeValues {
  var corners: _NodeValues = [:]
  for (property, value) in node.styles where property.hasPrefix("border") && property.hasSuffix("radius") && !value.isEmpty {
    corners[property] = value
  }
  return corners
}
