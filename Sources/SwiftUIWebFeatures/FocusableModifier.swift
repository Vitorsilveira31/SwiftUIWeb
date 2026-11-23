@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// SwiftUI `focusable(_:)` / `focusable(_:interactions:)`: makes a
/// non-control view a keyboard focus target (so `onKeyPress` handlers on it
/// receive keys), or removes a control from the focus order when false.
public struct FocusInteractions: OptionSet, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let activate = FocusInteractions(rawValue: 1 << 0)
  public static let edit = FocusInteractions(rawValue: 1 << 1)
  public static let automatic: FocusInteractions = [.activate, .edit]
}

package nonisolated struct FocusableModifier: ViewModifier {
  package let isFocusable: Bool
  package init(isFocusable: Bool) { self.isFocusable = isFocusable }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    Self.apply(isFocusable && context.environment.isEnabled, to: node)
  }

  @MainActor private static func apply(_ focusable: Bool, to node: _RenderNode) {
    if case .fragment = node.kind {
      // Only the first rendered child becomes the focus target, keeping one
      // tab stop for the modified view.
      if let first = node.children.first { apply(focusable, to: first) }
      return
    }
    node.attributes["tabindex"] = focusable ? "0" : "-1"
    node.attributes["data-focus-enabled"] = focusable ? "true" : "false"
  }
}

public extension View {
  nonisolated func focusable(_ isFocusable: Bool = true) -> some View {
    _modified(FocusableModifier(isFocusable: isFocusable))
  }
  nonisolated func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> some View {
    _modified(FocusableModifier(isFocusable: isFocusable))
  }
}
