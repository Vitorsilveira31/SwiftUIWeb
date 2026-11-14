@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// SwiftUI's `ControlGroup`: semantically related controls laid out in a
/// row (a `role="group"` horizontal stack named by the optional label).
public nonisolated struct ControlGroup<Content: View, Label: View>: View {
  public typealias Body = Never
  let content: Content
  let label: Label?

  public nonisolated init(@ViewBuilder content: () -> Content) where Label == EmptyView {
    self.content = content()
    label = nil
  }

  public nonisolated init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.content = content()
    self.label = label()
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text {
    self.content = content()
    label = Text(LocalizedStringKey(String(title)).resolved)
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text { self.init(titleKey.resolved, content: content) }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content) where Label == Text {
    self.init(title, content: { content() })
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) where Label == Text { self.init(titleKey.resolved, systemImage: systemImage, content: content) }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = HStack(spacing: 8) { content }._render(in: context.child(_FiberKey("control-group")))
    node.classes.append("control-group")
    node.attributes["role"] = "group"
    node.attributes["data-control-kind"] = "control-group"
    if let label {
      let name = _accessibleLabels(label._render(in: context.child(_FiberKey("label")))).joined(separator: " ")
      if !name.isEmpty { _AccessibilityBackend.setLabel(name, on: node) }
    }
    return node
  }
}
