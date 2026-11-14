
/// SwiftUI's image paint: a `ShapeStyle` that tiles a portion of an image
/// across the area it fills, as `.image(_:sourceRect:scale:)` does.
///
/// The tile size depends on the image's natural size, which only the browser
/// knows. The CSS value is therefore the bare image URL, and the renderer marks
/// the painted element so the browser host can size the tile from the decoded
/// image (`natural × sourceRect × scale`) once it loads. Static hosts keep the
/// image at its natural size.
public struct ImagePaint: ShapeStyle {
  public typealias Resolved = Never
  public var image: Image
  public var sourceRect: CGRect
  public var scale: CGFloat

  public init(image: Image, sourceRect: CGRect = _SwiftUIWebGeometryDefaults.unitRect, scale: CGFloat = 1) {
    self.image = image
    self.sourceRect = sourceRect
    self.scale = scale
  }

  /// The CSS value of the bare image. Renderers use `_paintCSSValue`, which also
  /// resolves asset-catalog names (that resolution is main-actor isolated).
  /// A remote URL in Apple's `Image("name")` loads nothing, as on Apple platforms (see `_ImageAssets.source(for:)`).
  public var _swiftUIWebCSSValue: String {
    image.allowsRemoteSource || _ImageAssets.isLocalPath(image.source) ? _cssQuotedURL(image.source) : "none"
  }
}

/// A CSS `url("…")` token for an application-supplied source. The source is
/// written into a quoted CSS string, so a quote or backslash is escaped and
/// control characters (which cannot appear in a CSS string or a URL) are
/// dropped. Nothing in the source can then end the string and start a new
/// declaration. Every other character is kept as written.
package func _cssQuotedURL(_ source: String) -> String {
  var result = "url(\""
  for scalar in source.unicodeScalars {
    switch scalar {
    case "\"", "\\":
      result += "\\"
      result.unicodeScalars.append(scalar)
    case _ where scalar.value < 0x20 || scalar.value == 0x7F:
      continue
    default:
      result.unicodeScalars.append(scalar)
    }
  }
  return result + "\")"
}

public extension ShapeStyle where Self == ImagePaint {
  static func image(_ image: Image, sourceRect: CGRect = _SwiftUIWebGeometryDefaults.unitRect, scale: CGFloat = 1) -> ImagePaint {
    ImagePaint(image: image, sourceRect: sourceRect, scale: scale)
  }
}

/// The renderer-facing value of an `ImagePaint`: the image source and the
/// tile geometry. Hashable so an erased `AnyShapeStyle` keeps it. `source` is
/// as the application spelled it; renderers resolve asset names with `_resolvedImagePaint`.
package struct _ImagePaintDescriptor: Hashable, Sendable {
  package let source: String
  package let sourceRect: CGRect
  package let scale: CGFloat
  /// The image came from `Image(_:alt:)` or an `AsyncImage` load, so a remote source is kept (see `_ImageAssets.source`).
  package var allowsRemoteSource = false

  package init(source: String, sourceRect: CGRect, scale: CGFloat, allowsRemoteSource: Bool = false) {
    self.allowsRemoteSource = allowsRemoteSource
    self.source = source
    self.sourceRect = sourceRect
    self.scale = scale
  }

  package var cssValue: String { _cssQuotedURL(source) }

  /// Attributes the browser host reads to size the tile. The host multiplies
  /// the natural image size by `sourceRect` and `scale`.
  package var markerAttributes: [(name: String, value: String)] {
    [
      ("data-image-paint", "true"),
      ("data-image-paint-source", source),
      ("data-image-paint-rect", [sourceRect.origin.x, sourceRect.origin.y, sourceRect.size.width, sourceRect.size.height].map(_imagePaintNumber).joined(separator: ",")),
      ("data-image-paint-scale", _imagePaintNumber(scale)),
    ]
  }
}

private func _imagePaintNumber(_ value: CGFloat) -> String {
  let number = Double(value)
  return Int64(exactly: number).map { String($0) } ?? String(number)
}

/// The image paint a style carries (an `ImagePaint` or an erased one), with
/// asset-catalog names resolved to the bundled file the browser loads.
@MainActor package func _resolvedImagePaint<S: ShapeStyle>(_ style: S) -> _ImagePaintDescriptor? {
  guard let paint = (style as? ImagePaint).map({ _ImagePaintDescriptor(source: $0.image.source, sourceRect: $0.sourceRect, scale: $0.scale, allowsRemoteSource: $0.image.allowsRemoteSource) }) ?? (style as? AnyShapeStyle)?._imagePaint,
    let source = _ImageAssets.source(for: paint.source, allowsRemote: paint.allowsRemoteSource)
  else { return nil }
  return _ImagePaintDescriptor(source: source, sourceRect: paint.sourceRect, scale: paint.scale, allowsRemoteSource: paint.allowsRemoteSource)
}

/// The paint value a renderer writes into CSS: the resolved image for an
/// image paint, and the style's own CSS value for every other style.
@MainActor package func _paintCSSValue<S: ShapeStyle>(_ style: S) -> String {
  if style is HierarchicalShapeStyle { return _foregroundPaintCSSValue(style) }
  return _resolvedImagePaint(style)?.cssValue ?? style._swiftUIWebCSSValue
}

/// Marks a painted element as an image paint for the browser host. Other styles are left untouched.
@MainActor package func _applyImagePaintMarkers<S: ShapeStyle>(_ style: S, to node: _RenderNode) {
  guard let paint = _resolvedImagePaint(style) else { return }
  for (name, value) in paint.markerAttributes { node.attributes[name] = value }
}

/// The SVG realization of an image paint: a `<pattern>` whose tile holds the
/// image. The browser host sets the tile and image geometry from the natural
/// size, so the pattern clips the image to the `sourceRect` tile.
@MainActor package func _svgImagePaintDefinition<S: ShapeStyle>(_ style: S, paint: _ImagePaintDescriptor, attribute: String, to path: _RenderNode, context: _RenderContext) -> _RenderNode {
  let id = _svgGradientIdentifier(style, attribute: attribute, context: context)
  let defs = _RenderNode.element("defs")
  let pattern = _RenderNode.element("pattern")
  pattern.attributes["id"] = id
  pattern.attributes["patternUnits"] = "userSpaceOnUse"
  for (name, value) in paint.markerAttributes { pattern.attributes[name] = value }
  let image = _RenderNode.element("image")
  image.attributes["href"] = paint.source
  image.attributes["preserveAspectRatio"] = "none"
  pattern.children = [image]
  defs.children = [pattern]
  _setSVGPaint(path, attribute, "url(#\(id))")
  return defs
}
