@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

public extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
  /// The innermost enclosing scroll view's visible area.
  static var scrollView: NamedCoordinateSpace { NamedCoordinateSpace(key: _GeometrySpaceKeys.scrollView) }

  /// The innermost enclosing scroll view that scrolls along `axis`.
  static func scrollView(axis: Axis) -> NamedCoordinateSpace {
    if axis == .horizontal { return NamedCoordinateSpace(key: _GeometrySpaceKeys.scrollViewHorizontal) }
    if axis == .vertical { return NamedCoordinateSpace(key: _GeometrySpaceKeys.scrollViewVertical) }
    return NamedCoordinateSpace(key: _GeometrySpaceKeys.scrollView)
  }
}
