// SwiftUI declarations that large shared apps use and that need no renderer support of their own: types applications
// name, environment values with a default, and semantic modifiers whose effect a browser realizes elsewhere or not at
// all (window management, matched geometry between views, input labels).

@_spi(Renderer) import SwiftUIWebTransferable

// MARK: Toolbars

/// A toolbar's items are views here, so `ToolbarContent` refines `View`; the builder's own output types (tuples,
/// `if` branches) conform too, which is what lets `@ToolbarContentBuilder` be the ordinary view builder.
@MainActor @preconcurrency public protocol ToolbarContent: View {}
public typealias ToolbarContentBuilder = ViewBuilder
extension ToolbarItem: ToolbarContent {}
extension ToolbarItemGroup: ToolbarContent {}
extension TupleView: ToolbarContent {}
extension _ConditionalContent: ToolbarContent where TrueContent: View, FalseContent: View {}
extension EmptyView: ToolbarContent {}
extension Group: ToolbarContent {}

// MARK: Layout direction and size classes

public enum LayoutDirection: Hashable, Sendable { case leftToRight, rightToLeft }

private enum LayoutDirectionKey: EnvironmentKey { static let defaultValue = LayoutDirection.leftToRight }

public extension EnvironmentValues {
  var layoutDirection: LayoutDirection {
    get { self[LayoutDirectionKey.self] }
    set { self[LayoutDirectionKey.self] = newValue }
  }
}

// MARK: Windows

// MARK: Semantic modifiers

extension _ViewBuilderContent: ToolbarContent {}

// MARK: Share previews

// MARK: Progress view styles

@MainActor @preconcurrency public protocol ProgressViewStyle { nonisolated var _swiftUIWebProgressStyle: String { get } }
public extension ProgressViewStyle { nonisolated var _swiftUIWebProgressStyle: String { "automatic" } }
public nonisolated struct DefaultProgressViewStyle: ProgressViewStyle { public nonisolated init() {} }
public nonisolated struct CircularProgressViewStyle: ProgressViewStyle {
  var tint: Color?
  public nonisolated init(tint: Color? = nil) { self.tint = tint }
  public nonisolated var _swiftUIWebProgressStyle: String { "circular" }
}
public nonisolated struct LinearProgressViewStyle: ProgressViewStyle {
  var tint: Color?
  public nonisolated init(tint: Color? = nil) { self.tint = tint }
  public nonisolated var _swiftUIWebProgressStyle: String { "linear" }
}
public extension ProgressViewStyle where Self == DefaultProgressViewStyle { @MainActor @preconcurrency static var automatic: DefaultProgressViewStyle { DefaultProgressViewStyle() } }
public extension ProgressViewStyle where Self == CircularProgressViewStyle { static nonisolated var circular: CircularProgressViewStyle { CircularProgressViewStyle() } }
public extension ProgressViewStyle where Self == LinearProgressViewStyle { static nonisolated var linear: LinearProgressViewStyle { LinearProgressViewStyle() } }

private enum ProgressViewStyleKey: EnvironmentKey { static let defaultValue = "automatic" }

extension EnvironmentValues {
  package var _progressViewStyle: String {
    get { self[ProgressViewStyleKey.self] }
    set { self[ProgressViewStyleKey.self] = newValue }
  }
}

// MARK: Transactions, transitions, accessibility representation

/// A navigation push that grows out of a source view (iOS 18). The browser pushes with its own transition.
/// The view-transition name of a matched view: one per (namespace, id), so the same pair names the same element in the
/// document. `vt-` keeps it a valid CSS identifier (it cannot start with a digit).
package func _viewTransitionName<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> String {
  "vt-" + namespace._stableIdentity + "-" + String(_distinctIDNumber(id))
}

/// One distinct id and the number handed to it. Stored type-erased (the typed storage checks the id's type on read), so
/// the table is one non-generic global: Embedded Swift has no static stored properties in generic types.
private struct _DistinctIDEntry<ID: Hashable> {
  let id: ID
  let number: Int
}
/// Ids and their numbers, keyed by the id's hash, probing to the next key when another id holds it, so a collision still
/// gets its own number. A bounded table starts again empty when full: an id seen again then gets a new number.
private final class _DistinctIDTable {
  private var storage = _TypedValueStorage<Int>()
  private var count = 0
  private let capacity: Int?

  init(capacity: Int?) { self.capacity = capacity }

  func number<ID: Hashable>(for id: ID) -> Int {
    var key = id.hashValue
    while storage.contains(key) {
      if let entry = storage.value(for: key, as: _DistinctIDEntry<ID>.self), entry.id == id { return entry.number }
      key = key &+ 1
    }
    let number = _newDistinctNumber()
    if let capacity, count >= capacity {
      storage = _TypedValueStorage<Int>()
      count = 0
      key = id.hashValue
    }
    storage.set(_DistinctIDEntry(id: id, number: number), for: key)
    count += 1
    return number
  }
}

/// Names the page relies on for as long as they exist (coordinate spaces, view transitions): never forgotten, so an
/// ancestor's `.coordinateSpace(name:)` and a later `.named(_:)` lookup always agree.
nonisolated(unsafe) private var _stableDistinctIDs = _DistinctIDTable(capacity: nil)
/// Environment value stamps, which only decide whether a memoized render can be reused: bounded, so an application
/// that writes ever-changing values does not grow it forever (a forgotten value costs one render).
nonisolated(unsafe) private var _memoDistinctIDs = _DistinctIDTable(capacity: 4_096)
/// The last number handed out, shared by both tables and by the environment's unique stamps (`_newDistinctNumber`), so
/// that no two of them ever share one.
nonisolated(unsafe) private var _lastDistinctIDNumber = 0

/// A fresh positive number, never handed out before in this process.
func _newDistinctNumber() -> Int {
  _lastDistinctIDNumber += 1
  return _lastDistinctIDNumber
}

/// A positive number unique to `id` (by its `==`) and stable for the process: for names the page keeps.
func _distinctIDNumber<ID: Hashable>(_ id: ID) -> Int { _stableDistinctIDs.number(for: id) }

/// A positive number unique to `id` (by its `==`), which may change after many other values: for memo stamps.
func _memoDistinctIDNumber<ID: Hashable>(_ id: ID) -> Int { _memoDistinctIDs.number(for: id) }

/// Writes the view-transition name as the element's `view-transition-name` style. Nil leaves the element unnamed. The element
/// is also recorded with the stack being rendered, so a zoom destination rendered after it can take the name over.
package nonisolated struct ViewTransitionNameModifier: ViewModifier {
  package let name: String?
  package init(name: String?) { self.name = name }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard let name else { return }
    node.styles["view-transition-name"] = name
    context.navigationContext?.transitionSources[name] = node
  }
}

/// A navigation transition. `zoom` names the source it grows from; the zoom destination takes that source's name while it is
/// on the stack (see `NavigationTransitionModifier`). `automatic`, and a zoom with no source, are a plain push.

public struct NavigationTransition: Sendable {
  package let sourceName: String?
  package init(sourceName: String?) { self.sourceName = sourceName }
  public static let automatic = NavigationTransition(sourceName: nil)
  public static func zoom(sourceID: some Hashable, in namespace: Namespace.ID) -> NavigationTransition {
    NavigationTransition(sourceName: _viewTransitionName(id: sourceID, in: namespace))
  }
}

/// Gives the destination the name of its source, rendered earlier in the same stack, and takes the name off that source while the
/// destination is shown: the name is on one element at a time. With no source rendered, the destination carries no name.
package nonisolated struct NavigationTransitionModifier: ViewModifier {
  package let transition: NavigationTransition
  package init(transition: NavigationTransition) { self.transition = transition }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard let name = transition.sourceName, let navigation = context.navigationContext,
          let source = navigation.transitionSources[name] else { return }
    source.styles.removeValue(forKey: "view-transition-name")
    node.styles["view-transition-name"] = name
  }
}

// MARK: Presentation, list and scene modifiers without a browser counterpart

/// SwiftUI's control group style. The browser lays out every control group the same way, so
/// `controlGroupStyle(_:)` accepts any style and does not change the rendering.
@MainActor @preconcurrency
public protocol ControlGroupStyle {
  associatedtype Body: View
  typealias Configuration = ControlGroupStyleConfiguration
  @MainActor @preconcurrency @ViewBuilder func makeBody(configuration: Self.Configuration) -> Body
}

public struct ControlGroupStyleConfiguration {
  @MainActor @preconcurrency public struct Content: View {
    public typealias Body = Never
    package let view: AnyView
    package init(view: AnyView) { self.view = view }
    public func _render(in context: _RenderContext) -> _RenderNode { view._render(in: context) }
  }
  @MainActor @preconcurrency public struct Label: View {
    public typealias Body = Never
    package let view: AnyView
    package init(view: AnyView) { self.view = view }
    public func _render(in context: _RenderContext) -> _RenderNode { view._render(in: context) }
  }
  public let content: Content
  public let label: Label
  package init(content: Content, label: Label) { self.content = content; self.label = label }
}

public nonisolated struct AutomaticControlGroupStyle: ControlGroupStyle {
  package let name: String
  package init(name: String) { self.name = name }
  nonisolated public func makeBody(configuration: AutomaticControlGroupStyle.Configuration) -> some View { configuration.content }
}

public nonisolated struct MenuControlGroupStyle: ControlGroupStyle {
  public nonisolated init() {}
  nonisolated public func makeBody(configuration: MenuControlGroupStyle.Configuration) -> some View { configuration.content }
}

public nonisolated struct NavigationControlGroupStyle: ControlGroupStyle {
  public nonisolated init() {}
  nonisolated public func makeBody(configuration: NavigationControlGroupStyle.Configuration) -> some View { configuration.content }
}

public extension ControlGroupStyle where Self == AutomaticControlGroupStyle {
  @MainActor @preconcurrency static var automatic: AutomaticControlGroupStyle { AutomaticControlGroupStyle(name: "automatic") }
}

public extension ControlGroupStyle where Self == MenuControlGroupStyle {
  static nonisolated var menu: MenuControlGroupStyle { MenuControlGroupStyle() }
}

public extension ControlGroupStyle where Self == NavigationControlGroupStyle {
  @MainActor @preconcurrency static var navigation: NavigationControlGroupStyle { NavigationControlGroupStyle() }
}

// MARK: Optionals, insets, deprecated accessibility spellings, small environment values

/// `Text?` (a computed badge that may be absent) draws its text or nothing, as a view builder's `if let` would.
/// Only `Text` has the conformance: a general `Optional: View` makes every optional a view candidate and slows
/// overload resolution in large view builders to a crawl.
extension Optional: View where Wrapped == Text {
  public typealias Body = Never
  public func _render(in context: _RenderContext) -> _RenderNode {
    switch self {
    case .some(let view): return view._render(in: context)
    case .none: return .empty()
    }
  }
}

public extension View {

  nonisolated func padding(_ insets: EdgeInsets) -> some View {
    padding(.top, insets.top).padding(.leading, insets.leading).padding(.bottom, insets.bottom).padding(.trailing, insets.trailing)
  }

  nonisolated func font(_ font: Font?) -> some View { self.font(font ?? Font.body) }

}

public extension HorizontalAlignment {
  static let listRowSeparatorLeading = HorizontalAlignment.leading
  static let listRowSeparatorTrailing = HorizontalAlignment.trailing
}


public extension Binding {
  /// `$flag.animation()`: writes through the binding animate.
  func animation(_ animation: Animation? = .default) -> Binding<Value> {
    Binding(_unchecked: { self.wrappedValue }, set: { newValue in withAnimation(animation) { self.wrappedValue = newValue } })
  }
}

// MARK: Sections, pickers, edit mode

// MARK: Tab placement

public extension View {
  /// `.mask(shape)` takes the mask view directly.
  nonisolated func mask<Mask: View>(_ mask: Mask) -> some View {
    modifier(MaskCompatibilityModifier(mask: { mask }))
  }
}

public struct _HashableIdentified<Value: Hashable>: Identifiable {
  public let value: Value
  public var id: Value { value }
  init(_ value: Value) { self.value = value }
}

