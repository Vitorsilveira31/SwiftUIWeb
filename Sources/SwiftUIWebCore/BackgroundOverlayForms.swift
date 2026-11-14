/// SwiftUI's value (non-builder) spellings of `background` and `overlay`.
///
/// `Color`, gradients and other paints are both `View`s and `ShapeStyle`s.
/// The view forms are disfavored so `.background(Color.red)`,
/// `.overlay(LinearGradient(...))` and `.overlay(.black.opacity(0.2))` keep
/// resolving to the paint forms (one filled layer across the whole bounds),
/// while ordinary views such as `.overlay(Text("New"), alignment: .topTrailing)`
/// or `.background(RoundedRectangle(cornerRadius: 8).stroke())` use the layered
/// view path. Both routes produce the same layer structure as the
/// `alignment:content:` builders.
public extension View {
  @_disfavoredOverload
  nonisolated func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> some View {
    modifier(BackgroundModifier(content: { background }, alignment: alignment))
  }

  @_disfavoredOverload
  nonisolated func overlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> some View {
    modifier(OverlayModifier(content: { overlay }, alignment: alignment))
  }

  /// Layers a paint over the view's bounds.
  nonisolated func overlay<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
    nonisolated(unsafe) let style = style
    return modifier(OverlayModifier(content: { _ShapeView(shape: Rectangle(), style: style, stroke: nil) }, alignment: .center))
  }

  /// Layers a paint, clipped to `shape`, over the view's bounds.
  nonisolated func overlay<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
    nonisolated(unsafe) let shape = shape
    nonisolated(unsafe) let style = style
    return modifier(OverlayModifier(content: { _ShapeView(shape: shape, style: style, stroke: nil, fillStyle: fillStyle) }, alignment: .center))
  }

  /// Fills the view's bounds with the environment's background style.
  nonisolated func background(ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
    background(BackgroundStyle(), ignoresSafeAreaEdges: edges)
  }

  /// Fills `shape` behind the view with the environment's background style.
  nonisolated func background<T: Shape>(in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
    background(BackgroundStyle(), in: shape, fillStyle: fillStyle)
  }
}
