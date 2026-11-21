/// SwiftUI's `LabelStyle` family (`.labelStyle(.iconOnly)`, custom styles).
public struct LabelStyleConfiguration {
  public struct Title {
    public typealias Body = Never
    let content: AnyView
    @MainActor public func _render(in context: _RenderContext) -> _RenderNode { content._render(in: context) }
  }
  public struct Icon {
    public typealias Body = Never
    let content: AnyView
    @MainActor public func _render(in context: _RenderContext) -> _RenderNode { content._render(in: context) }
  }
  public let title: Title
  public let icon: Icon
}
extension LabelStyleConfiguration.Title: View {}
extension LabelStyleConfiguration.Icon: View {}

@MainActor @preconcurrency
public protocol LabelStyle {
  associatedtype Body: View
  typealias Configuration = LabelStyleConfiguration
  @MainActor @preconcurrency @ViewBuilder func makeBody(configuration: Self.Configuration) -> Body
  /// Renderer hook identifying the built-in styles without a dynamic cast
  /// (unavailable in Embedded Swift). Custom styles keep the default.
  nonisolated var _swiftUIWebLabelStyleKind: _LabelStyleKind { get }
}

public extension LabelStyle {
  nonisolated var _swiftUIWebLabelStyleKind: _LabelStyleKind { .custom }
}

public nonisolated struct DefaultLabelStyle: LabelStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: DefaultLabelStyle.Configuration) -> some View { HStack { configuration.icon; configuration.title } }
  public nonisolated var _swiftUIWebLabelStyleKind: _LabelStyleKind { .automatic }
}

public nonisolated struct TitleAndIconLabelStyle: LabelStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: TitleAndIconLabelStyle.Configuration) -> some View { HStack { configuration.icon; configuration.title } }
  public nonisolated var _swiftUIWebLabelStyleKind: _LabelStyleKind { .titleAndIcon }
}

public nonisolated struct IconOnlyLabelStyle: LabelStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: IconOnlyLabelStyle.Configuration) -> some View { configuration.icon }
  public nonisolated var _swiftUIWebLabelStyleKind: _LabelStyleKind { .iconOnly }
}

public nonisolated struct TitleOnlyLabelStyle: LabelStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: TitleOnlyLabelStyle.Configuration) -> some View { configuration.title }
  public nonisolated var _swiftUIWebLabelStyleKind: _LabelStyleKind { .titleOnly }
}

public extension LabelStyle where Self == DefaultLabelStyle { @MainActor @preconcurrency static var automatic: DefaultLabelStyle { DefaultLabelStyle() } }
public extension LabelStyle where Self == TitleAndIconLabelStyle { static nonisolated var titleAndIcon: TitleAndIconLabelStyle { TitleAndIconLabelStyle() } }
public extension LabelStyle where Self == IconOnlyLabelStyle { static nonisolated var iconOnly: IconOnlyLabelStyle { IconOnlyLabelStyle() } }
public extension LabelStyle where Self == TitleOnlyLabelStyle { static nonisolated var titleOnly: TitleOnlyLabelStyle { TitleOnlyLabelStyle() } }

/// Built-in styles are resolved by the Label renderer (so `.iconOnly` keeps
/// the title as the accessible name); custom styles render their body.
public enum _LabelStyleKind: Equatable, Sendable { case automatic, titleAndIcon, iconOnly, titleOnly, custom }

package struct _LabelStyleRenderer: Sendable {
  let kind: _LabelStyleKind
  let render: (@MainActor (LabelStyleConfiguration) -> AnyView)?
  package init(kind: _LabelStyleKind, render: (@MainActor (LabelStyleConfiguration) -> AnyView)?) {
    self.kind = kind
    self.render = render
  }
}

private enum LabelStyleEnvironmentKey: EnvironmentKey { static let defaultValue: _LabelStyleRenderer? = nil }

extension EnvironmentValues {
  package var _labelStyle: _LabelStyleRenderer? {
    get { self[LabelStyleEnvironmentKey.self] }
    set { self[LabelStyleEnvironmentKey.self] = newValue }
  }
}

extension Label {
  @MainActor func _renderLabel(title: Title, icon: Icon, in context: _RenderContext) -> _RenderNode {
    let style = context.environment._labelStyle
    if let style, style.kind == .custom, let render = style.render {
      let configuration = LabelStyleConfiguration(
        title: LabelStyleConfiguration.Title(content: AnyView(title)),
        icon: LabelStyleConfiguration.Icon(content: AnyView(icon))
      )
      return render(configuration)._render(in: context.child(_FiberKey("label-style")))
    }
    let node = _RenderNode.element("label")
    node.classes = ["icon-label", "hstack"]
    // The icon and the title are laid out as a row, so the label takes its natural width instead of being measured
    // as an opaque box that a parent stack can squeeze.
    node.attributes["data-layout-kind"] = "hstack"
    node.attributes["data-layout-schema"] = "1"
    // In a sidebar, as on iPad, the icon sits in a column of its own, 30 points wide, so every title starts at the same
    // place whatever its icon's width, 7 points after it (Food Truck's sidebar, measured on an iPad mini).
    let sidebar = context.environment._isInSidebar
    node.attributes["data-layout-gap"] = _semanticNumber(sidebar ? 7 : 8)
    node.attributes["data-align-x"] = "0.5"
    node.attributes["data-align-y"] = "0.5"
    let kind = style?.kind ?? .automatic
    let iconNode = sidebar
      ? icon.frame(width: 30)._render(in: context.child(_FiberKey("icon")))
      : icon._render(in: context.child(_FiberKey("icon")))
    let titleNode = title._render(in: context.child(_FiberKey("title")))
    switch kind {
    case .iconOnly:
      // The title stays the accessible name of the icon-only label.
      let name = _accessibleLabels(titleNode).joined(separator: " ")
      if !name.isEmpty { _AccessibilityBackend.setLabel(name, on: node) }
      node.attributes["data-label-style"] = "icon-only"
      node.children = [iconNode]
    case .titleOnly:
      node.attributes["data-label-style"] = "title-only"
      node.children = [titleNode]
    default:
      node.children = [iconNode, titleNode]
    }
    return node
  }
}
