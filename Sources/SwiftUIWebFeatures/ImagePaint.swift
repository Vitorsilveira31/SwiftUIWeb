@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// The marker attributes of an image paint, for `Text`, whose style modifiers
/// are not main-actor isolated and so keep the source as the application spelled it.
package func _unresolvedImagePaintMarkers<S: ShapeStyle>(_ style: S) -> [(name: String, value: String)] {
  guard let paint = (style as? ImagePaint).map({ _ImagePaintDescriptor(source: $0.image.source, sourceRect: $0.sourceRect, scale: $0.scale) }) ?? (style as? AnyShapeStyle)?._imagePaint else { return [] }
  return paint.markerAttributes
}
