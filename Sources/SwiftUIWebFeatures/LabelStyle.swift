@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

package nonisolated struct LabelStyleModifier: ViewModifier {
  let renderer: _LabelStyleRenderer
  @MainActor package func _modifyContext(_ context: inout _RenderContext) { context.environment._labelStyle = renderer }
}

public extension View {
  nonisolated func labelStyle<S: LabelStyle>(_ style: S) -> some View {
    let kind = style._swiftUIWebLabelStyleKind
    // A main-actor closure is Sendable, so it may only capture Sendable values; a main-actor box holds the style.
    let box = _MainActorBox(style)
    var render: (@MainActor (LabelStyleConfiguration) -> AnyView)?
    if kind == .custom { render = { AnyView(box.value.makeBody(configuration: $0)) } }
    return modifier(LabelStyleModifier(renderer: _LabelStyleRenderer(kind: kind, render: render)))
  }
}
