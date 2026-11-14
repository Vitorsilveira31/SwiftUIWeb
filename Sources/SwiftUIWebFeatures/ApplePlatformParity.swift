@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable

public protocol CustomizableToolbarContent: ToolbarContent {}

/// Space between toolbar items; the browser toolbar lays items out with its own gaps.
public nonisolated struct ToolbarSpacer: ToolbarContent {
  public typealias Body = Never
  public nonisolated init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic) {}
  public func _render(in context: _RenderContext) -> _RenderNode { .empty() }
}

/// How much room a `ToolbarSpacer` takes.
public struct SpacerSizing: Hashable, Sendable {
  let name: String
  public static let flexible = SpacerSizing(name: "flexible")
  public static let fixed = SpacerSizing(name: "fixed")
}

public extension ToolbarContent {
  /// Whether toolbar items share one glass background; the browser toolbar draws a single bar.
  nonisolated func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent { self }
}

public extension CustomizableToolbarContent {
  nonisolated func sharedBackgroundVisibility(_ visibility: Visibility) -> some CustomizableToolbarContent { self }
}

public enum UserInterfaceSizeClass: Hashable, Sendable { case compact, regular }

private enum HorizontalSizeClassKey: EnvironmentKey { static let defaultValue: UserInterfaceSizeClass? = .regular }

private enum VerticalSizeClassKey: EnvironmentKey { static let defaultValue: UserInterfaceSizeClass? = .regular }

public extension EnvironmentValues {
  /// `.regular` unless the application sets it from the viewport (`.environment(\.horizontalSizeClass, ...)`).
  var horizontalSizeClass: UserInterfaceSizeClass? {
    get { self[HorizontalSizeClassKey.self] }
    set { self[HorizontalSizeClassKey.self] = newValue }
  }

  var verticalSizeClass: UserInterfaceSizeClass? {
    get { self[VerticalSizeClassKey.self] }
    set { self[VerticalSizeClassKey.self] = newValue }
  }
}

/// A browser page is one window; asking for another has no effect.
@MainActor @preconcurrency public struct OpenWindowAction: Sendable {
  public func callAsFunction(id: String) {}
  public func callAsFunction<Value: Hashable>(value: Value) {}
  public func callAsFunction<Value: Hashable>(id: String, value: Value) {}
}

@MainActor @preconcurrency public struct DismissWindowAction: Sendable {
  @MainActor @preconcurrency public func callAsFunction() {}
  @MainActor @preconcurrency public func callAsFunction(id: String) {}
}

private enum OpenWindowKey: EnvironmentKey { static let defaultValue = OpenWindowAction() }

private enum DismissWindowKey: EnvironmentKey { static let defaultValue = DismissWindowAction() }

public extension EnvironmentValues {
  var openWindow: OpenWindowAction {
    get { self[OpenWindowKey.self] }
    set { self[OpenWindowKey.self] = newValue }
  }

  var dismissWindow: DismissWindowAction {
    get { self[DismissWindowKey.self] }
    set { self[DismissWindowKey.self] = newValue }
  }
}

/// Which parts of a view's frame `matchedGeometryEffect` matches.
@frozen public struct MatchedGeometryProperties: OptionSet, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  /// The position of the view's anchor point.
  public static let position = MatchedGeometryProperties(rawValue: 1 << 0)
  /// The view's size.
  public static let size = MatchedGeometryProperties(rawValue: 1 << 1)
  /// Both: the whole frame.
  public static let frame = MatchedGeometryProperties(rawValue: (1 << 0) | (1 << 1))

  public typealias ArrayLiteralElement = MatchedGeometryProperties
  public typealias Element = MatchedGeometryProperties
  public typealias RawValue = UInt32
}

/// The attributes the page reads a matched geometry by: the source of a name, or a view that takes its frame, with the
/// parts of the frame matched and the anchor point.
nonisolated struct _MatchedGeometryModifier: ViewModifier {
  let name: String
  let properties: MatchedGeometryProperties
  let anchor: UnitPoint
  let isSource: Bool
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes[isSource ? "data-matched-source" : "data-matched-target"] = name
    // The default, the whole frame at the center, needs no attribute.
    if properties != .frame { node.attributes["data-matched-properties"] = properties == .position ? "position" : properties == .size ? "size" : "none" }
    if anchor != .center { node.attributes["data-matched-anchor"] = _transitionNumber(anchor.x) + " " + _transitionNumber(anchor.y) }
  }
}

public extension View {
  /// Views that share an id in a namespace share their geometry. The source names its element for the browser's view
  /// transition, so that a source replaced by another morphs into it with the commit's animation; a view that is not
  /// the source takes the source's frame (the parts `properties` names, aligned at `anchor`), which the page places it at
  /// and moves it to when the source moves (`data-matched-*`, transition-host.js).
  nonisolated func matchedGeometryEffect<ID: Hashable>(id: ID, in namespace: Namespace.ID, properties: MatchedGeometryProperties = .frame, anchor: UnitPoint = .center, isSource: Bool = true) -> some View {
    let name = _viewTransitionName(id: id, in: namespace)
    // Only the source names the element: a second element with the name would abort the browser transition.
    return modifier(ViewTransitionNameModifier(name: isSource ? name : nil))
      .modifier(_MatchedGeometryModifier(name: name, properties: properties, anchor: anchor, isSource: isSource))
  }

  @_disfavoredOverload nonisolated func accessibilityInputLabels<S: StringProtocol>(_ inputLabels: [S]) -> some View { self }

  nonisolated func accessibilityInputLabels(_ labels: [Text]) -> some View { self }

  nonisolated func accessibilityInputLabels(_ labels: [LocalizedStringKey]) -> some View { self }

  nonisolated func accessibilityRespondsToUserInteraction(_ respondsToUserInteraction: Bool = true) -> some View { self }

  nonisolated func accessibilityLabel(_ key: LocalizedStringKey) -> some View { accessibilityLabel(key.resolved) }

  nonisolated func accessibilityValue(_ key: LocalizedStringKey) -> some View { accessibilityValue(key.resolved) }

  nonisolated func accessibilityHint(_ key: LocalizedStringKey) -> some View { accessibilityHint(key.resolved) }
}

public extension View {
  /// Keyboard-focus ring suppression; the browser's focus ring is controlled by the stylesheet.
  nonisolated func focusEffectDisabled(_ disabled: Bool = true) -> some View { self }

  /// Quick Look is an Apple preview panel; a browser opens files through the link itself.
  nonisolated func quickLookPreview(_ item: Binding<URL?>) -> some View { self }
}

public extension AccessibilityTraits {
  static let startsMediaSession = AccessibilityTraits(rawValue: 1 << 7)

  static let playsSound = AccessibilityTraits(rawValue: 1 << 8)

  static let allowsDirectInteraction = AccessibilityTraits(rawValue: 1 << 9)

  static let causesPageTurn = AccessibilityTraits(rawValue: 1 << 10)

  static let isSummaryElement = AccessibilityTraits(rawValue: 1 << 11)

  static let isStaticText = AccessibilityTraits(rawValue: 1 << 12)

  static let isKeyboardKey = AccessibilityTraits(rawValue: 1 << 13)

  static let isSearchField = AccessibilityTraits(rawValue: 1 << 14)

  static let isToggle = AccessibilityTraits(rawValue: 1 << 15)

  static let isModal = AccessibilityTraits(rawValue: 1 << 16)
}

/// What a share sheet shows for an item. The browser's share sheet shows the page's own preview, so only the
/// title is kept.
public struct SharePreview<Image, Icon>: Sendable {
  let title: String
  @_disfavoredOverload public init<S: StringProtocol>(_ title: S, image: Image) where Icon == Never { self.title = String(title) }
  @_disfavoredOverload public init<S: StringProtocol>(_ title: S, image: Image, icon: Icon) { self.title = String(title) }
  public init(_ title: LocalizedStringKey, image: Image) where Icon == Never { self.title = title.resolved }
  public init(_ title: LocalizedStringKey, image: Image, icon: Icon) { self.title = title.resolved }
  @_disfavoredOverload public init<S: StringProtocol>(_ title: S) where Image == Never, Icon == Never { self.title = String(title) }
  public init(_ title: LocalizedStringKey) where Image == Never, Icon == Never { self.title = title.resolved }
}

public extension ShareLink {
  nonisolated init<Item, I, Ic>(item: Item, subject: Text? = nil, message: Text? = nil, preview: SharePreview<I, Ic>, @ViewBuilder label: () -> Label) {
    self.init(described: _swiftUIWebDescribe(item), subject: subject ?? Text(verbatim: preview.title), message: message, label: label())
  }
}

public extension ShareLink where Label == Text {
  nonisolated init<Item, I, Ic>(item: Item, subject: Text? = nil, message: Text? = nil, preview: SharePreview<I, Ic>) {
    self.init(described: _swiftUIWebDescribe(item), subject: subject ?? Text(verbatim: preview.title), message: message, label: Text("Share"))
  }
}

public extension View {
  nonisolated func progressViewStyle<S: ProgressViewStyle>(_ style: S) -> some View {
    let token = style._swiftUIWebProgressStyle
    return modifier(EnvironmentOverride(apply: { $0._progressViewStyle = token }))
  }
}


public extension View {
  nonisolated func navigationTransition(_ style: NavigationTransition) -> some View { modifier(NavigationTransitionModifier(transition: style)) }

  nonisolated func matchedTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
    modifier(ViewTransitionNameModifier(name: _viewTransitionName(id: id, in: namespace)))
  }

  /// The representation replaces the accessibility tree of the view in SwiftUI; the browser exposes the view's own
  /// DOM, which already carries its labels.
  nonisolated func accessibilityRepresentation<Representation: View>(@ViewBuilder representation: () -> Representation) -> some View { self }
}

public struct PresentationSizing: Sendable {
  public static let automatic = PresentationSizing(), form = PresentationSizing(), page = PresentationSizing(), fitted = PresentationSizing()
}

public struct AccessibilityActionKind: Hashable, Sendable {
  let name: String
  public static let `default` = AccessibilityActionKind(name: "default")
  public static let escape = AccessibilityActionKind(name: "escape")
  public static let magicTap = AccessibilityActionKind(name: "magicTap")
}

public nonisolated struct CompactMenuControlGroupStyle: ControlGroupStyle {
  public nonisolated init() {}
  nonisolated public func makeBody(configuration: CompactMenuControlGroupStyle.Configuration) -> some View { configuration.content }
}

public nonisolated struct PaletteControlGroupStyle: ControlGroupStyle {
  public nonisolated init() {}
  nonisolated public func makeBody(configuration: PaletteControlGroupStyle.Configuration) -> some View { configuration.content }
}

public extension ControlGroupStyle where Self == CompactMenuControlGroupStyle {
  static nonisolated var compactMenu: CompactMenuControlGroupStyle { CompactMenuControlGroupStyle() }
}

public extension ControlGroupStyle where Self == PaletteControlGroupStyle {
  @MainActor @preconcurrency static var palette: PaletteControlGroupStyle { PaletteControlGroupStyle() }
}

public enum WindowResizability: Sendable { case automatic, contentSize, contentMinSize }

public extension View {
  nonisolated func listSectionSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View { self }

  nonisolated func presentationBackground<S: ShapeStyle>(_ style: S) -> some View { self }

  nonisolated func presentationBackground<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { self }

  nonisolated func presentationCornerRadius(_ cornerRadius: CGFloat?) -> some View { self }

  nonisolated func presentationSizing(_ sizing: PresentationSizing) -> some View { self }

  nonisolated func accessibilitySortPriority(_ sortPriority: Double) -> some View { self }

  nonisolated func accessibilityAction(named name: Text, _ handler: @escaping () -> Void) -> some View { self }

  @_disfavoredOverload nonisolated func accessibilityAction<S: StringProtocol>(named name: S, _ handler: @escaping () -> Void) -> some View { self }

  nonisolated func accessibilityAction(named key: LocalizedStringKey, _ handler: @escaping () -> Void) -> some View { self }

  nonisolated func accessibilityAction(_ actionKind: AccessibilityActionKind = .default, _ handler: @escaping () -> Void) -> some View { self }

  nonisolated func edgesIgnoringSafeArea(_ edges: Edge.Set) -> some View { self }

  nonisolated func controlGroupStyle<S: ControlGroupStyle>(_ style: S) -> some View { self }

  nonisolated func safeAreaBar(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
    let bar = content()
    return safeAreaInset(edge: edge, alignment: alignment, spacing: spacing.map { Double($0) }) { bar }
  }

  nonisolated func safeAreaBar(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
    let bar = content()
    return safeAreaInset(edge: edge, alignment: alignment, spacing: spacing.map { Double($0) }) { bar }
  }

  nonisolated func searchScopes<Scope: Hashable, Scopes: View>(_ scope: Binding<Scope>, @ViewBuilder scopes: () -> Scopes) -> some View { self }

  nonisolated func searchScopes<Scope: Hashable, Scopes: View>(_ scope: Binding<Scope>, activation: SearchScopeActivation, @ViewBuilder _ scopes: () -> Scopes) -> some View { self }
}

/// SwiftUI's `SearchScopeActivation`: when a search's scopes appear. A browser page has no system search field
/// to attach them to, so the value is accepted and nothing is drawn.
public enum SearchScopeActivation: Hashable, Sendable {
  case automatic
  case onTextEntry
  case onSearchPresentation
}

public extension Image {
  enum TemplateRenderingMode: Sendable { case template, original }

  /// Template images take the foreground color; the browser draws symbols and masks that way already.
  func renderingMode(_ renderingMode: Image.TemplateRenderingMode?) -> Image { self }
}

public extension Scene {
  nonisolated func defaultSize(width: CGFloat, height: CGFloat) -> Self { self }

  nonisolated func windowResizability(_ resizability: WindowResizability) -> Self { self }
}

public extension View {
  @_disfavoredOverload
  nonisolated func foregroundColor(_ color: Color?) -> some View {
    foregroundStyle(color ?? Color.primary)
  }

  nonisolated func accessibilityActions<Content: View>(@ViewBuilder _ content: () -> Content) -> some View { self }

  // Deprecated spellings that shared code still uses.
  nonisolated func accessibility(label: Text) -> some View { accessibilityLabel(label) }

  nonisolated func accessibility(hint: Text) -> some View { accessibilityHint(hint) }

  nonisolated func accessibility(value: Text) -> some View { accessibilityValue(value) }

  nonisolated func accessibility(addTraits traits: AccessibilityTraits) -> some View { accessibilityAddTraits(traits) }

  nonisolated func accessibility(hidden: Bool) -> some View { accessibilityHidden(hidden) }

  nonisolated func accessibility(identifier: String) -> some View { accessibilityIdentifier(identifier) }
}

public extension Angle {
  init(degrees: Double) { self.init(radians: degrees * 0.017453292519943295) }
}

private enum VoiceOverKey: EnvironmentKey { static let defaultValue = false }

private enum MinRowHeightKey: EnvironmentKey { static let defaultValue: Double = 44 }

public extension EnvironmentValues {
  /// A browser cannot tell whether a screen reader is running.
  var accessibilityVoiceOverEnabled: Bool {
    get { self[VoiceOverKey.self] }
    set { self[VoiceOverKey.self] = newValue }
  }

  var defaultMinListRowHeight: Double {
    get { self[MinRowHeightKey.self] }
    set { self[MinRowHeightKey.self] = newValue }
  }

  var symbolVariants: SymbolVariants {
    get { self[SymbolVariantsKey.self] }
    set { self[SymbolVariantsKey.self] = newValue }
  }
}

private enum SymbolVariantsKey: EnvironmentKey { static let defaultValue = SymbolVariants.none }

public extension Animation {
  static var smooth: Animation { smooth() }

  static var bouncy: Animation { bouncy() }

  static var spring: Animation { spring() }
}

/// Moves keyboard focus for assistive technology; the browser's focus order is the document's.
@propertyWrapper public struct AccessibilityFocusState<Value: Hashable>: DynamicProperty {
  private let storage: FocusState<Value>
 public init() where Value == Bool { storage = FocusState() }
  public init<T: Hashable>() where Value == T? { storage = FocusState() }
 public var wrappedValue: Value {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }
 public var projectedValue: AccessibilityFocusState<Value>.Binding { Binding(binding: storage.projectedValue.binding) }

  /// `$focus`: what `accessibilityFocused(_:)` takes.
  @propertyWrapper public struct Binding {
    let binding: SwiftUIWebCore.Binding<Value>
    public var wrappedValue: Value {
      get { binding.wrappedValue }
      nonmutating set { binding.wrappedValue = newValue }
    }
    public var projectedValue: AccessibilityFocusState<Value>.Binding { self }
  }
}

public extension View {
  nonisolated func accessibilityFocused(_ condition: AccessibilityFocusState<Bool>.Binding) -> some View { self }

  nonisolated func accessibilityFocused<Value: Hashable>(_ binding: AccessibilityFocusState<Value>.Binding, equals value: Value) -> some View { self }
}

public extension Section {
  init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) where Header == EmptyView {
    self.init(content: content, header: { EmptyView() }, footer: footer)
  }

  init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) where Footer == EmptyView {
    self.init(content: content, header: header, footer: { EmptyView() })
  }

  init(header: Header, footer: Footer, @ViewBuilder content: () -> Content) {
    self.init(content: content, header: { header }, footer: { footer })
  }

  init(header: Header, @ViewBuilder content: () -> Content) where Footer == EmptyView {
    self.init(content: content, header: { header }, footer: { EmptyView() })
  }

  init(footer: Footer, @ViewBuilder content: () -> Content) where Header == EmptyView {
    self.init(content: content, header: { EmptyView() }, footer: { footer })
  }
}

public extension Picker {
  nonisolated init<Label: View>(selection: Binding<SelectionValue>, label: Label, @ViewBuilder content: () -> Content) {
    self.init(selection: selection, content: content, label: { label })
  }
}

public enum EditMode: Hashable, Sendable {
  case inactive, transient, active
  public var isEditing: Bool { self != .inactive }
}

private enum EditModeKey: EnvironmentKey { static var defaultValue: Binding<EditMode>? { nil } }

public extension EnvironmentValues {
  /// Rows of an editable list show their handles when this is `.active`.
  var editMode: Binding<EditMode>? {
    get { self[EditModeKey.self] }
    set { self[EditModeKey.self] = newValue }
  }
}

public extension Animation {
  static var snappy: Animation { snappy() }
}

public enum TabPlacement: Hashable, Sendable { case automatic, pinned, sidebarOnly }

public struct TabBarPlacement: Hashable, Sendable {
  let name: String
  public static let sidebar = TabBarPlacement(name: "sidebar")
}

/// Where an adaptable `TabView` (`.sidebarAdaptable`) shows its tabs.
public struct AdaptableTabBarPlacement: Hashable, Sendable {
  let name: String
  public static let automatic = AdaptableTabBarPlacement(name: "automatic")
  public static let sidebar = AdaptableTabBarPlacement(name: "sidebar")
  public static let tabBar = AdaptableTabBarPlacement(name: "tabBar")
}

// `TabContent` itself lives in TabContent.swift; this extension is the
// placement modifier Apple declares on it.
public extension TabContent {
  /// The browser's tab strip has no pinned or sidebar-only split, so placement is accepted and the tab keeps its slot.
  nonisolated func tabPlacement(_ placement: TabPlacement) -> some TabContent<TabValue> { self }
}

public extension View {
  nonisolated func defaultTabBarPlacement(_ placement: AdaptableTabBarPlacement) -> Self { self }
}

public extension Text {
  nonisolated func monospaced(_ isActive: Bool = true) -> Text { isActive ? _styled("font-family", "ui-monospace, SFMono-Regular, Menlo, monospace") : self }
}

/// Toggles the environment's edit mode.
public nonisolated struct EditButton: View {
  public typealias Body = Never
  public nonisolated init() {}
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // Read the environment from the render context rather than through
    // `@Environment(\.editMode)`: Core's own key-path property wrappers need
    // the Embedded `_embedded:` spelling, which only app source gets from the
    // lowering pass.
    let binding = context.environment.editMode
    let active = binding?.wrappedValue == .active
    return Button(active ? "Done" : "Edit") {
      binding?.wrappedValue = active ? .inactive : .active
    }._render(in: context)
  }
}
