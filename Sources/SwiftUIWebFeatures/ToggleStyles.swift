@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

package nonisolated struct ToggleStyleModifier: ViewModifier {
  let style: String
  init(style: String) { self.style = style }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) { context.environment._toggleStyle = style }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-toggle-style"] = style
  }
}

public extension View {
  nonisolated func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
    modifier(ToggleStyleModifier(style: style._swiftUIWebToggleStyle))
  }
}
