@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

public extension View {
  /// Centers the view at `(x, y)` in its parent's coordinate space. Like
  /// SwiftUI the positioned view takes the whole proposed size (the layout's
  /// `position` node) and the content keeps its own size.
  nonisolated func position(x: CGFloat = 0, y: CGFloat = 0) -> some View {
    modifier(StyleModifier(styles: [:], semantic: [
      "data-layout-kind": "position",
      "data-position-x": _semanticNumber(Double(x)),
      "data-position-y": _semanticNumber(Double(y))
    ]))
  }

  nonisolated func position(_ position: CGPoint) -> some View {
    self.position(x: position.x, y: position.y)
  }

  /// Offsets rendering without changing layout (SwiftUI's `offset(_:)`).
  nonisolated func offset(_ offset: CGSize) -> some View {
    self.offset(x: Double(offset.width), y: Double(offset.height))
  }
}
