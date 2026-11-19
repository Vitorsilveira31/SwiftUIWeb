@_spi(Renderer) import SwiftUIWebTransferable
/// The neutral history operation emitted by a navigation container. A browser
/// adapter can translate these operations to pushState/replaceState/back and
/// forward without exposing JavaScript or DOM types to application Views.
package enum NavigationHistoryOperation: Equatable {
  case push(path: String)
  case replace(path: String)
  case back(path: String)
}

package protocol NavigationHistoryAdapter {
  func _scope(_ identity: String) -> NavigationHistoryAdapter
  func apply(_ operation: NavigationHistoryOperation)
  /// Maps a logical path to a URL. Browser adapters can override this to
  /// produce human-readable routes; the default is deterministic and based on
  /// the stable Fiber keys.
  func path(for navigationPath: NavigationPath) -> String
  /// Receives the complete logical path before an operation is committed.
  /// Browser adapters use it to associate a URL/history entry with the typed
  /// `NavigationPath`, without exposing route storage to application code.
  func update(_ navigationPath: NavigationPath)
  /// Installs a callback for browser-originated history changes. Non-browser
  /// adapters may keep the default no-op implementation.
  func observe(_ callback: @escaping (NavigationPath) -> Void)

  /// Tab selections use the same history boundary as pushed destinations.
  /// Keeping these hooks on the base protocol means the canonical Embedded
  /// browser path never needs a runtime cast to a platform-specific adapter.
  /// Existing adapters remain source-compatible through the no-op defaults
  /// below; browser adapters override them to persist the selected tab.
  func _updateTab(namespace: String, tag: String)
  func _observeTab(namespace: String, callback: @escaping (String) -> Void)
  /// Records the tab to restore when this history scope returns to its root.
  func _setTabDefault(namespace: String, tag: String)
}

/// Optional browser history specialization for tab selections. Keeping this
/// as a refinement rather than a required NavigationHistoryAdapter method
/// preserves source compatibility for existing application adapters.
package protocol _TabHistoryAdapter: NavigationHistoryAdapter {}

/// Optional renderer specialization. Nested stacks receive distinct state
/// observers while retaining the application's existing history API.
package extension NavigationHistoryAdapter {
  func _scope(_ identity: String) -> NavigationHistoryAdapter { self }
  func path(for navigationPath: NavigationPath) -> String {
    guard !navigationPath.elements.isEmpty else { return "/" }
    return "/" + navigationPath.elements.map(fiberKeyDescription).joined(separator: "/")
  }
  func update(_ navigationPath: NavigationPath) {}
  func observe(_ callback: @escaping (NavigationPath) -> Void) {}
  func _updateTab(namespace: String, tag: String) {
    _ = namespace
    _ = tag
  }
  func _observeTab(namespace: String, callback: @escaping (String) -> Void) {
    _ = namespace
    _ = callback
  }
  func _setTabDefault(namespace: String, tag: String) {
    _ = namespace
    _ = tag
  }
}

fileprivate final class _NavigationPathObserver {
  var previous: NavigationPath
  let history: NavigationHistoryAdapter

  init(previous: NavigationPath, history: NavigationHistoryAdapter) {
    var snapshot = previous
    snapshot.observer = nil
    self.previous = snapshot
    self.history = history
  }

  func changed(to next: NavigationPath) {
    let old = previous
    var snapshot = next
    snapshot.observer = nil
    previous = snapshot
    guard old.elements != next.elements else { return }

    history.update(next)

    if next.elements.count > old.elements.count,
       next.elements.starts(with: old.elements) {
      history.apply(.push(path: history.path(for: next)))
    } else if next.elements.count < old.elements.count,
              old.elements.starts(with: next.elements) {
      history.apply(.back(path: history.path(for: next)))
    } else {
      history.apply(.replace(path: history.path(for: next)))
    }
  }
}

/// SwiftUI-compatible path storage with an internal value payload used for
/// typed destination resolution. Hashing remains based on stable Fiber keys,
/// while the payload stays private to the navigation runtime.
public struct NavigationPath: Hashable {
  // Stable keys are runtime data, not part of SwiftUI's public NavigationPath
  // surface. Keep them private so Fiber identity never leaks into app code.
  fileprivate private(set) var elements: [_FiberKey]
  fileprivate var values: [_NavigationPathElement]
  fileprivate var observer: _NavigationPathObserver?

  public init() {
    elements = []
    values = []
    observer = nil
  }

  public init<S: Sequence>(_ sequence: S) where S.Element: Hashable {
    self.init()
    for value in sequence { append(value) }
  }

  public var count: Int { elements.count }
  public var isEmpty: Bool { elements.isEmpty }

  public mutating func append<V: Hashable>(_ value: V) {
    let key = _FiberKey(value)
    elements.append(key)
    values.append(_NavigationPathElement(key: key, value: _RuntimeValue(value), directDestination: nil))
    observer?.changed(to: self)
  }

  /// Additive web-friendly helper for authentication redirects and other
  /// replace-state flows. Standard SwiftUI code can continue assigning a new
  /// path or removing elements normally.
  package mutating func replaceLast<V: Hashable>(_ value: V) {
    guard !elements.isEmpty else { append(value); return }
    let key = _FiberKey(value)
    elements[elements.count - 1] = key
    values[values.count - 1] = _NavigationPathElement(key: key, value: _RuntimeValue(value), directDestination: nil)
    observer?.changed(to: self)
  }

  /// Convenience spelling for replacing the complete path with one value.
  package mutating func replace<V: Hashable>(_ value: V) {
    let key = _FiberKey(value)
    elements = [key]
    values = [_NavigationPathElement(key: key, value: _RuntimeValue(value), directDestination: nil)]
    observer?.changed(to: self)
  }

  public mutating func removeLast(_ k: Int = 1) {
    guard k > 0 else { return }
    let amount = min(k, elements.count)
    elements.removeLast(amount)
    values.removeLast(amount)
    observer?.changed(to: self)
  }

  package mutating func removeAll() {
    elements.removeAll(keepingCapacity: false)
    values.removeAll(keepingCapacity: false)
    observer?.changed(to: self)
  }

  public static func == (lhs: NavigationPath, rhs: NavigationPath) -> Bool {
    lhs.elements == rhs.elements
  }

  /// The path's values when every element has type `Element`, backing
  /// `NavigationStack(path: Binding<[Element]>)`. Destinations pushed by a
  /// value-less link cannot be represented in a typed path.
  func _typedElements<Element>(_ type: Element.Type) -> [Element]? {
    var result: [Element] = []
    result.reserveCapacity(values.count)
    for element in values {
      guard let value = element.value?.read(type) else { return nil }
      result.append(value)
    }
    return result
  }

  fileprivate var _observer: _NavigationPathObserver? {
    get { observer }
    set { observer = newValue }
  }

  // SwiftUI's NavigationPath declares no hash(into:) of its own; Hashable is
  // satisfied by this witness, which stays out of the public symbol graph.
  @_spi(Renderer) public func hash(into hasher: inout Hasher) {
    hasher.combine(elements)
  }

  /// Returns a copy suitable for a platform history adapter. The observer is
  /// intentionally omitted so storing a path in browser history cannot retain
  /// the navigation runtime or trigger a second callback when restored.
  public func _historySnapshot() -> NavigationPath {
    var copy = self
    copy.observer = nil
    return copy
  }

  /// Renderer-only stable route description. The backing Fiber keys remain
  /// private; browser adapters receive only the escaped logical path.
  @_spi(Renderer) public func _historyPathDescription() -> String {
    _navigationURLPath(self)
  }

  /// Reattaches the live observer when a platform history entry is restored.
  /// History snapshots intentionally omit callbacks so they are safe to
  /// retain, but replacing the app's bound path with such a snapshot must not
  /// silently disable future push/pop observation.
  fileprivate func _historyRestored(from snapshot: NavigationPath) -> NavigationPath {
    var copy = snapshot
    if let observer {
      // Browser history restoration bypasses `NavigationPath`'s mutating
      // methods, so the observer would otherwise retain the path from before
      // Back/Forward. Refresh its baseline as well as reattaching it; the
      // next user mutation must be compared with the restored entry.
      var restored = snapshot
      restored.observer = nil
      observer.previous = restored
      copy.observer = observer
    }
    return copy
  }

  fileprivate mutating func append(destination: AnyView, key: _FiberKey) {
    elements.append(key)
    values.append(_NavigationPathElement(key: key, value: nil, directDestination: { destination }))
    observer?.changed(to: self)
  }

  fileprivate mutating func appendURLKey(_ key: _FiberKey) {
    elements.append(key)
  }
}

fileprivate struct _NavigationPathElement {
  let key: _FiberKey
  let value: _RuntimeValue?
  let directDestination: (() -> AnyView)?
}

@inline(__always)
fileprivate func _navigationURLPath(_ path: NavigationPath) -> String {
  guard !path.elements.isEmpty else { return "/" }
  return "/" + path.elements.map(fiberKeyDescription).joined(separator: "/")
}

/// The href of a path when no history adapter formats it. Normalised as `BrowserHistoryAdapter.path(for:)` does: one
/// leading `/` and each segment percent-encoded, so a value such as "//host" cannot become a protocol-relative link.
fileprivate func _navigationHref(_ path: NavigationPath) -> String {
  let segments = _navigationURLPath(path).split(separator: "/").map { _navigationPercentEncodedSegment(String($0)) }
  return "/" + segments.joined(separator: "/")
}

private func _navigationPercentEncodedSegment(_ value: String) -> String {
  // "." and ".." are kept as escapes too: an href of them navigates up the path.
  if value == "." { return "%2E" }
  if value == ".." { return "%2E%2E" }
  var output = ""
  for byte in value.utf8 {
    let unreserved = (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
      || byte == 45 || byte == 46 || byte == 95 || byte == 126
    if unreserved {
      output.append(Character(UnicodeScalar(byte)))
    } else {
      output += "%" + (byte < 16 ? "0" : "") + String(byte, radix: 16, uppercase: true)
    }
  }
  return output
}

/// Decodes the private two-component path used by browser history adapters for
/// tab selection. It is SPI-only renderer plumbing; application navigation
/// paths never need to know about this marker.
@_spi(Renderer) public func _tabHistoryComponents(_ path: NavigationPath) -> (namespace: String, tag: String)? {
  guard path.elements.count == 2 else { return nil }
  let marker = fiberKeyDescription(path.elements[0])
  let prefix = "__tab:"
  guard marker.hasPrefix(prefix) else { return nil }
  return (String(marker.dropFirst(prefix.count)), fiberKeyDescription(path.elements[1]))
}

@_spi(Renderer) public func _tabHistoryNamespaceToken(_ namespace: String) -> String {
  String(_tabStableHashState(namespace), radix: 16)
}

fileprivate struct _NavigationDestinationEntry {
  let matches: (_RuntimeValue) -> Bool
  let build: (_RuntimeValue) -> AnyView

  init<Value: Hashable, Destination: View>(value: Value.Type, destination: @escaping (Value) -> Destination) {
    matches = { $0.typeID == _storedTypeID(Value.self) }
    build = { value in
      guard let value: Value = value.read() else { return AnyView(EmptyView()) }
      return AnyView(destination(value))
    }
  }
}

fileprivate struct _ActiveNavigationDestination {
  let isPresented: () -> Bool
  let dismiss: () -> Void
  let build: () -> AnyView
}

fileprivate final class _NavigationDestinationRegistry {
  var entries: [_NavigationDestinationEntry] = []
  var active: [_ActiveNavigationDestination] = []

  @MainActor func register<Value: Hashable, Destination: View>(value: Value.Type, destination: @escaping (Value) -> Destination) {
    entries.append(_NavigationDestinationEntry(value: value, destination: destination))
  }

  func resolve(_ value: _RuntimeValue) -> AnyView? {
    for entry in entries.reversed() where entry.matches(value) {
      return entry.build(value)
    }
    return nil
  }
}

/// What a navigation stack has built so far, between its stages.
final class _NavigationStackBuild {
  var children: [_RenderNode] = []
  var depth = 0
  var rootToolbar: _RenderNode?
  var rootChrome = _NavigationBarChrome()
  var destinationToolbar: _RenderNode?
  var destinationChrome = _NavigationBarChrome()
}

/// What a pushed screen asks of its own navigation bar: `navigationBarBackButtonHidden(_:)` and
/// `toolbar(_:for: .navigationBar)`. Collected while the screen's toolbars are extracted.
struct _NavigationBarChrome {
  var hidesBackButton = false
  var hidesBar = false
}

/// Collection point for navigation modifiers that are applied outside the
/// NavigationStack value. SwiftUI permits both placements; this holder lets
/// the stack adopt those declarations when it creates its runtime context.
final class _NavigationSetup {
  fileprivate let registry = _NavigationDestinationRegistry()
  fileprivate var title: String?
  fileprivate var titleDisplayMode: NavigationBarItem.TitleDisplayMode = .automatic
}

/// Runtime context shared by a NavigationStack's root and destination Fibers.
/// It is intentionally an implementation detail; app code uses NavigationPath,
/// NavigationLink, navigationDestination, and @Environment(\.dismiss).
final class NavigationContext {
  fileprivate let path: Binding<NavigationPath>
  fileprivate let registry = _NavigationDestinationRegistry()
  fileprivate let history: NavigationHistoryAdapter?
  fileprivate var directCounter = 0
  fileprivate var currentDismiss: () -> Void = {}
  deinit { _RenderThreadState.current.closureGraveyard.bury(&currentDismiss) }
  /// The element that carries each view-transition name, as last rendered: the source a zoom destination takes the name from
  /// (see `NavigationTransitionModifier`). One node per name: a destination that re-renders on its own registers its source
  /// again, and the latest registration replaces the one before it, so nothing accumulates between stack renders.
  var transitionSources: [String: _RenderNode] = .init()
  fileprivate var title: String?
  /// Toolbars declared by `.toolbar { }` while the stack renders a screen. A screen's own state can re-render it
  /// without the stack; keeping toolbars out of the screen's tree makes that render the same shape as a full one.
  var toolbarSink = _OrderedValues<_RenderNode>()
  var collectingToolbars = false

  func beginToolbarCollection() { toolbarSink.removeAll(); collectingToolbars = true }
  func endToolbarCollection() -> [_RenderNode] {
    collectingToolbars = false
    let collected = toolbarSink.inOrder()
    toolbarSink.removeAll()
    return collected
  }
  fileprivate var titleDisplayMode: NavigationBarItem.TitleDisplayMode = .automatic

  fileprivate init(path: Binding<NavigationPath>, history: NavigationHistoryAdapter?, setup: _NavigationSetup?) {
    self.path = path
    self.history = history
    if let setup {
      registry.entries = setup.registry.entries
      registry.active = setup.registry.active
      title = setup.title
      titleDisplayMode = setup.titleDisplayMode
    }
  }

  @MainActor fileprivate func push<Value: Hashable>(_ value: Value) {
    var next = path.wrappedValue
    next.append(value)
    path.wrappedValue = next
  }

  @MainActor fileprivate func push(destination: AnyView) {
    var next = path.wrappedValue
    directCounter += 1
    next.append(destination: destination, key: _FiberKey("destination-\(directCounter)"))
    path.wrappedValue = next
  }

  @MainActor fileprivate func dismiss() {
    // A path destination always dismisses by removing its last value. This
    // direct check keeps the action robust even when a destination's own
    // modifiers replace the contextual dismiss closure while rendering.
    if !path.wrappedValue.isEmpty {
      popPath()
    } else {
      currentDismiss()
    }
  }

  @MainActor fileprivate func popPath() {
    var next = path.wrappedValue
    guard !next.isEmpty else { return }
    next.removeLast()
    path.wrappedValue = next
  }

  fileprivate func registerActive(isPresented: @escaping () -> Bool, dismiss: @escaping () -> Void, build: @escaping () -> AnyView) {
    _renderRegistersWithAncestors()
    registry.active.append(_ActiveNavigationDestination(isPresented: isPresented, dismiss: dismiss, build: build))
  }

  fileprivate func resolve(_ element: _NavigationPathElement) -> AnyView? {
    if let directDestination = element.directDestination { return directDestination() }
    guard let value = element.value else { return nil }
    return registry.resolve(value)
  }

  @MainActor fileprivate func href(for key: _FiberKey?) -> String {
    guard let key else { return "#navigation" }
    var preview = path.wrappedValue
    preview.appendURLKey(key)
    return history?.path(for: preview) ?? _navigationHref(preview)
  }

}

/// SwiftUI spells the title display mode as `NavigationBarItem.TitleDisplayMode`.
public enum NavigationBarItem {
  public enum TitleDisplayMode: Hashable, Sendable {
    case automatic, inline, large

    /// The value written to the host's `data-navigation-title-display-mode` attribute.
    var _attributeValue: String {
      switch self {
      case .automatic: return "automatic"
      case .inline: return "inline"
      case .large: return "large"
      }
    }
  }
}

/// A SwiftUI-shaped navigation container. Root and destination nodes remain in
/// one Fiber subtree so unaffected state can be retained across path updates.
public nonisolated struct NavigationStack<Content: View>: View {
  public typealias Body = Never
  let content: Content
  private let pathBinding: Binding<NavigationPath>?
  private let history: NavigationHistoryAdapter?
  @State(memberID: 905793607) private var internalPath = NavigationPath()
  @State(memberID: 905793608) private var mixedBase: NavigationPath? = nil
  @State(memberID: 905793609) private var pathRevision = 0

  nonisolated public init(@ViewBuilder root: () -> Content) {
    self.content = root()
    pathBinding = nil
    history = nil
  }

  package init(path: Binding<NavigationPath>, history: NavigationHistoryAdapter? = nil, @ViewBuilder content: () -> Content) {
    self.content = content()
    pathBinding = path
    self.history = history
  }

  /// SwiftUI's spelling of the path initializer.
  nonisolated public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Content) {
    self.init(path: path, history: nil, content: root)
  }

  /// A stack whose path is a homogeneous collection of values, as in
  /// `NavigationStack(path: $routes)` with `@State var routes: [Route]`.
  nonisolated public init<Data>(path: Binding<Data>, @ViewBuilder root: () -> Content)
  where Data: MutableCollection & RandomAccessCollection & RangeReplaceableCollection,
        Data.Element: Hashable {
    self.content = root()
    pathBinding = _typedNavigationPathBinding(path)
    isTypedPath = { $0._typedElements(Data.Element.self) != nil }
    history = nil
  }

  /// Set by the typed-collection initializer: tells whether a path holds only values of the collection's type.
  private var isTypedPath: ((NavigationPath) -> Bool)?

  @MainActor private var resolvedPath: Binding<NavigationPath> {
    guard let pathBinding else { return $internalPath }
    guard let isTypedPath else { return pathBinding }
    // A typed collection cannot hold the destination a `NavigationLink(destination:)` pushes. While the stack shows
    // one, the full path lives in the stack's own state, over the typed path it was pushed onto.
    let mixed = $internalPath, base = $mixedBase, revision = $pathRevision
    return Binding(
      get: {
        // Reading the revision makes the stack itself re-render when its path changes, whichever model owns the
        // collection: a push adds a screen to the stack's own tree, and updating only the model's reader leaves
        // that tree in the wrong place.
        _ = revision.wrappedValue
        let typed = pathBinding.wrappedValue
        guard !mixed.wrappedValue.isEmpty, let recorded = base.wrappedValue, recorded == typed else { return typed }
        var result = mixed.wrappedValue
        result._observer = typed._observer
        return result
      },
      set: { next in
        let before = pathBinding.wrappedValue
        pathBinding.wrappedValue = next
        if isTypedPath(next) {
          // Written only when something changes: a state write schedules a render, and the history observer
          // sets the path again on every render.
          if !mixed.wrappedValue.isEmpty { mixed.wrappedValue = NavigationPath() }
          if base.wrappedValue != nil { base.wrappedValue = nil }
        } else {
          base.wrappedValue = pathBinding.wrappedValue
          mixed.wrappedValue = next
        }
        if next != before { revision.wrappedValue &+= 1 }
      }
    )
  }

  @MainActor private func installHistoryObserver(on binding: Binding<NavigationPath>, history: NavigationHistoryAdapter?) {
    guard let history else { return }
    let current = binding.wrappedValue
    // A stack is evaluated for every Fiber refresh. Installing a new observer
    // on every pass resets the previous-path snapshot and registers duplicate
    // browser callbacks, which makes push/pop appear to stop working after
    // the first interaction. The observer travels with the path value and is
    // only installed again when callers replace the path with a fresh value.
    guard current.observer == nil else { return }
    let observer = _NavigationPathObserver(previous: current, history: history)
    var observed = current
    observed.observer = observer
    binding.wrappedValue = observed
    history.observe { next in
      // Browser back/forward supplies the same typed path that was associated
      // with the history entry. Updating the binding drives the normal Fiber
      // reconciliation path; assigning the restored snapshot does not invoke
      // the observer's mutation hook a second time.
      let current = binding.wrappedValue
      binding.wrappedValue = current._historyRestored(from: next)
    }
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let pathBinding = resolvedPath
    let candidate = history ?? context.environment.navigationHistory
    let activeHistory = history ?? candidate?._scope(context._fiberPath.description)
    installHistoryObserver(on: pathBinding, history: activeHistory)
    let navigation = NavigationContext(path: pathBinding, history: activeHistory, setup: context.navigationSetup)
    // At the root of a stack that a sheet presents, `dismiss()` closes that sheet.
    let enclosingDismiss = context.environment.dismiss
    navigation.currentDismiss = { enclosingDismiss() }
    var local = context
    local.navigationContext = navigation
    local.environment.dismiss = DismissAction { navigation.dismiss() }

    navigation.beginToolbarCollection()
    // The stack gathers what its content registered once the pass has rendered it: the content's deferred parts
    // included, and the stacks nested in it first (see `_StagedRender`).
    _RenderStaging.enterStage()
    let renderedRoot = content._render(in: local)
    _RenderStaging.exitStage()
    let built = _NavigationStackBuild()
    return _RenderStaging.stagedNode { stage in
      stage.whenSettled { stage in
        var rootToolbars = navigation.endToolbarCollection()
        var rootChrome = _NavigationBarChrome()
        let root = _extractNavigationToolbars(from: renderedRoot, into: &rootToolbars, chrome: &rootChrome)
        let path = resolvedPath.wrappedValue

        // A toolbar belongs to the nearest navigation container, even when the
        // modifier was declared by a deeply nested screen. Moving the semantic
        // node here keeps app views free to own their local presentation state
        // while the browser renders one stable bar outside scrollable content.
        built.rootToolbar = _combinedNavigationToolbar(rootToolbars)
        built.rootChrome = rootChrome

        if !root.isEmpty {
          let rootContainer = _RenderNode.element("div")
          rootContainer.classes = ["navigation-root"]
          if !path.isEmpty { rootContainer.attributes["aria-hidden"] = "true" }
          rootContainer.children = [root]
          built.children.append(rootContainer)
        }
        let values = Array(path.values)
        self._renderDestination(0, of: values, navigation: navigation, local: local, built: built, stage: stage, finish: {
          stage in self._finishStack(navigation: navigation, local: local, path: path, built: built, stage: stage)
        })
      }
    }
  }

  /// Renders the destination at `index` and the ones after it, each gathered once the pass has rendered it.
  @MainActor private func _renderDestination(
    _ index: Int, of values: [_NavigationPathElement], navigation: NavigationContext, local: _RenderContext,
    built: _NavigationStackBuild, stage: _StagedRender,
    finish: @escaping @MainActor (_StagedRender) -> Void
  ) {
    guard index < values.count, let destination = navigation.resolve(values[index]) else {
      finish(stage)
      return
    }
    navigation.currentDismiss = navigation.popPath
    // Include both stack depth and the path value in the state scope. This
    // keeps two equal route types at different depths independent and resets
    // a replaced value's local state instead of reusing a sibling's box.
    var destinationContext = local.child(_FiberKey("destination-\(index)")).child(values[index].key)
    destinationContext.environment.dismiss = DismissAction { navigation.dismiss() }
    navigation.beginToolbarCollection()
    _RenderStaging.enterStage()
    let renderedDestination = destination._render(in: destinationContext)
    _RenderStaging.exitStage()
    stage.whenSettled { stage in
      var destinationToolbars = navigation.endToolbarCollection()
      var destinationChrome = _NavigationBarChrome()
      let destinationNode = _extractNavigationToolbars(
        from: renderedDestination, into: &destinationToolbars, chrome: &destinationChrome)
      if index == values.count - 1 {
        built.destinationToolbar = _combinedNavigationToolbar(destinationToolbars)
        built.destinationChrome = destinationChrome
      }
      let container = _RenderNode.element("div")
      container.classes = ["navigation-destination"]
      container.attributes["data-navigation-depth"] = "\(index + 1)"
      // NavigationStack keeps the complete destination chain in Fiber so
      // state can be retained while pushing and popping. Only the top
      // destination is visible to users; the browser stylesheet hides the
      // inactive snapshots while preserving them for reconciliation.
      if index < values.count - 1 {
        container.attributes["data-navigation-inactive"] = "true"
        container.attributes["aria-hidden"] = "true"
      }
      container.children = [destinationNode]
      built.children.append(container)
      built.depth = index + 1
      self._renderDestination(index + 1, of: values, navigation: navigation, local: local, built: built, stage: stage, finish: finish)
    }
  }

  /// The end of the stack's render: the bar, the presented destination and the node's own attributes.
  @MainActor private func _finishStack(
    navigation: NavigationContext, local: _RenderContext, path: NavigationPath,
    built: _NavigationStackBuild, stage: _StagedRender
  ) {
    var renderedChildren = built.children
    var renderedDepth = built.depth
    // The bar of the screen on top: a hidden bar reserves no space and draws no title, as in SwiftUI.
    let barHidden = path.isEmpty ? built.rootChrome.hidesBar : built.destinationChrome.hidesBar
    // Keep a root toolbar (for example the app's menu button) visible while a
    // destination has no replacement toolbar. A destination toolbar replaces
    // it only when the destination explicitly declares one.
    // A hidden navigation bar takes the top items with it; the items of the bottom bar stay, as in SwiftUI.
    func bottomItemsOnly(_ toolbar: _RenderNode?) -> _RenderNode? {
      guard let toolbar else { return nil }
      let items = (toolbar.kind == .fragment ? toolbar.children : [toolbar]).filter(_isBottomBarToolbarItem)
      guard !items.isEmpty else { return nil }
      let bottom = _RenderNode.fragment()
      bottom.attributes["role"] = "toolbar"
      bottom.children = items
      return bottom
    }
    if path.isEmpty {
      if let rootToolbar = built.rootToolbar {
        if !barHidden { renderedChildren.insert(rootToolbar, at: 0) } else if let bottom = bottomItemsOnly(rootToolbar) { renderedChildren.insert(bottom, at: 0) }
      }
    } else if renderedDepth > 0, barHidden {
      if let bottom = bottomItemsOnly(built.destinationToolbar) { renderedChildren.insert(bottom, at: 0) }
    } else if renderedDepth > 0 {
      // A pushed screen has its own bar, as in SwiftUI: a back button and whatever the screen declares. The root
      // screen's toolbar belongs to the root and is not carried over. `navigationBarBackButtonHidden(true)` removes
      // the system back button only; the screen's own toolbar items stay.
      var barItems = built.destinationToolbar.map { $0.kind == .fragment ? $0.children : [$0] } ?? []
      if !built.destinationChrome.hidesBackButton {
        let back = ToolbarItem(placement: .navigationBarLeading) {
          Button { navigation.popPath() } label: { Image(systemName: "chevron.left") }
            .accessibilityLabel("Back")
        }._render(in: local.child(_FiberKey("back")))
        barItems.insert(back, at: 0)
      }
      if !barItems.isEmpty {
        let bar = _RenderNode.fragment()
        bar.attributes["role"] = "toolbar"
        bar.children = barItems
        renderedChildren.insert(bar, at: 0)
      }
    }

    if let active = navigation.registry.active.last(where: { $0.isPresented() }) {
      // A presented destination is pushed over the screen on top, which is then hidden as a pushed screen hides it in
      // SwiftUI (the containers were made by this render, so they are not shared).
      if let top = renderedChildren.lastIndex(where: { $0.classes.contains("navigation-root") || $0.classes.contains("navigation-destination") }) {
        renderedChildren[top].attributes["aria-hidden"] = "true"
        if renderedChildren[top].classes.contains("navigation-destination") { renderedChildren[top].attributes["data-navigation-inactive"] = "true" }
      }
      navigation.currentDismiss = active.dismiss
      var destinationContext = local.child(_FiberKey("active-destination"))
      destinationContext.environment.dismiss = DismissAction { navigation.dismiss() }
      let destinationNode = active.build()._render(in: destinationContext)
      let container = _RenderNode.element("div")
      container.classes = ["navigation-destination", "navigation-presented"]
      container.attributes["data-navigation-depth"] = "\(renderedDepth + 1)"
      container.children = [destinationNode]
      renderedChildren.append(container)
      renderedDepth += 1
    }

    // Items placed in `ToolbarItemPlacement.bottomBar` leave the top bar and form a bar at the foot of the screen, as
    // iOS's bottom toolbar does; a bar left with no top item goes away.
    var bottomItems: [_RenderNode] = []
    renderedChildren = renderedChildren.compactMap { child in
      guard child.attributes["role"] == "toolbar" else { return child }
      let items = child.kind == .fragment ? child.children : [child]
      let bottom = items.filter(_isBottomBarToolbarItem)
      guard !bottom.isEmpty else { return child }
      bottomItems += bottom
      let top = items.filter { !_isBottomBarToolbarItem($0) }
      guard !top.isEmpty else { return nil }
      let remaining = _RenderNode.fragment()
      remaining.attributes["role"] = "toolbar"
      remaining.children = top
      return remaining
    }
    if !bottomItems.isEmpty {
      let bottomBar = _RenderNode.element("div")
      bottomBar.classes = ["navigation-bottom-bar"]
      bottomBar.children = bottomItems
      renderedChildren.append(bottomBar)
    }

    let node = _RenderNode.element("main")
    node.classes = ["navigation-stack"]
    node.attributes["data-navigation-depth"] = "\(renderedDepth)"
    if let title = navigation.title { node.attributes["data-navigation-title"] = title }
    node.attributes["data-navigation-title-display-mode"] = navigation.titleDisplayMode._attributeValue
    if barHidden { node.attributes["data-navigation-bar-hidden"] = "true" }
    node.children = renderedChildren
    stage.complete(node)
  }
}

/// Whether a toolbar item or group (`ToolbarItem` and `ToolbarItemGroup` write their placement on different attributes)
/// belongs to the bottom bar.
private func _isBottomBarToolbarItem(_ node: _RenderNode) -> Bool {
  node.attributes["data-toolbar-placement"] == ToolbarItemPlacement.bottomBar.rawValue
    || node.attributes["data-toolbar-group-placement"] == ToolbarItemPlacement.bottomBar.rawValue
}

/// Moves toolbar nodes out of a screen's tree. The tree may be a cached or retained node the reconciler still
/// compares against, so it is never edited in place: a node whose subtree held a toolbar is copied instead.
///
/// A loop with an explicit stack, visiting in the order a recursion would: a screen can be as deep as the layout allows,
/// and a call per level would put a limit on it.
private func _extractNavigationToolbars(
  from root: _RenderNode, into toolbars: inout [_RenderNode], chrome: inout _NavigationBarChrome
) -> _RenderNode {
  guard !root.isEmpty else { return root }
  // Modifiers on the screen (or on any view inside it, outside a nested stack) decide its bar.
  func note(_ node: _RenderNode) {
    if node.attributes["data-navigation-back-button-hidden"] == "true" { chrome.hidesBackButton = true }
    if node.attributes[_toolbarVisibilityAttribute(.navigationBar)] == "hidden" { chrome.hidesBar = true }
  }
  note(root)
  struct Level {
    let node: _RenderNode
    let children: [_RenderNode]
    var next = 0
    var retained: [_RenderNode] = []
    var changed = false
    init(_ node: _RenderNode) {
      self.node = node
      children = node.children
      retained.reserveCapacity(children.count)
    }
  }
  var stack = [Level(root)]
  while var level = stack.popLast() {
    if level.next < level.children.count {
      let child = level.children[level.next]
      level.next += 1
      if !child.classes.contains("navigation-stack") { note(child) }
      if child.attributes["role"] == "toolbar" {
        toolbars.append(child)
        level.changed = true
        stack.append(level)
      } else if child.classes.contains("navigation-stack") || child.isEmpty {
        // A nested stack (a sheet's own NavigationStack) owns the toolbars declared inside it.
        level.retained.append(child)
        stack.append(level)
      } else {
        stack.append(level)
        stack.append(Level(child))
      }
      continue
    }
    var replacement = level.node
    if level.changed {
      replacement = level.node.cloneSharingChildren()
      replacement.children = level.retained
    }
    guard var parent = stack.popLast() else { return replacement }
    if replacement !== level.node { parent.changed = true }
    parent.retained.append(replacement)
    stack.append(parent)
  }
  return root
}

private func _combinedNavigationToolbar(_ toolbars: [_RenderNode]) -> _RenderNode? {
  guard !toolbars.isEmpty else { return nil }
  guard toolbars.count > 1 else { return toolbars[0] }
  let combined = _RenderNode.fragment()
  combined.attributes["role"] = "toolbar"
  // A toolbar of one item is that item's own node; only a fragment of several items is unwrapped.
  combined.children = toolbars.flatMap { $0.kind == .fragment ? $0.children : [$0] }
  return combined
}

/// How many tabs a `TabView` keeps built once the user has visited them.
///
/// `keepVisited` (the default) keeps every visited tab alive, as SwiftUI does:
/// going back to a tab shows it at once with its `@State`, and the page grows with
/// every tab opened. `recent(n)` keeps the selected tab plus the `n - 1` most
/// recently visited ones and rebuilds older tabs when they are opened again, like
/// a router that unmounts inactive routes. Keep durable state in your model layer
/// when you use it.
package enum TabViewMountPolicy: Hashable, Sendable {
  case keepVisited
  case recent(Int)
}

/// Builds a `Tab`'s content only once the tab has been selected, and keeps it
/// mounted afterwards (state preserved), like SwiftUI's TabView. Unselected,
/// never-visited tabs render a lightweight placeholder that still carries
/// their label, icon and badge for the tab bar. This keeps the DOM, the
/// snapshot and every layout pass proportional to the visited tabs.
/// A hidden tab that was built is not built again on every pass of the tab
/// view: its content hands back `_RenderNode._retainedRender`, and the Fiber
/// keeps what it shows, state and owners included (updates inside the tab
/// still reach it through its own owners). The selected tab is always built,
/// so a tab shown again catches up with what changed while it was hidden.
final class _TabMountTracker {
  private var order: [String] = []          // visited tabs, most recent last
  private var visited: Set<String> = []
  /// The tags of the tabs this view has rendered. A requested tag (from history, the URL or the app) that is not one of
  /// them is not recorded, so `visited` cannot grow without bound from data.
  private var knownTags: Set<String> = []
  private var requested: String?
  private var firstSeen: String?
  private var mountedThisPass: Set<String> = []
  /// The key of each tab's content as it was last built.
  private var builtKeys: [String: _FiberKey?] = .init()
  /// The size of the box the panels share (`tab-body`), as the host last measured it. A tab built for the first time
  /// starts its geometry readers at this size: the enclosing reader's size, which they would take otherwise, is the
  /// window when the sidebar narrows the panels, and a layout that depends on the width (a grid's column count) was
  /// laid out wide and corrected a round trip later.
  var panelSize: CGSize?

  func beginPass(requested: String?, policy: TabViewMountPolicy) {
    self.requested = requested
    firstSeen = nil
    mountedThisPass.removeAll(keepingCapacity: true)
    // Touch the requested tab before anything renders so tabs evicted by it
    // are not built one more time in this pass. Only a tab that exists is touched.
    if let requested, knownTags.contains(requested) { touch(requested, policy: policy) }
  }

  func shouldMount(_ tag: String) -> Bool {
    knownTags.insert(tag)
    if firstSeen == nil { firstSeen = tag }
    // Without an explicit selection TabView shows its first tab.
    let mount = visited.contains(tag) || tag == (requested ?? firstSeen)
    if mount { mountedThisPass.insert(tag) }
    return mount
  }

  /// Whether `tag` is built or about to be: a tab the pointer rests on is not prepared again.
  func isPrepared(_ tag: String) -> Bool { visited.contains(tag) }

  /// Builds `tag` before it is selected, hidden (the pointer rests on its tab button): a hidden tab runs no lifecycle
  /// (`onAppear`, `task`; see `FiberTree.lifecycleIsVisible`), so selecting it later shows content already built, as a
  /// revisit does. False when it is built already or the policy keeps a single tab, which the selected one is.
  func prepare(_ tag: String, policy: TabViewMountPolicy) -> Bool {
    guard !visited.contains(tag) else { return false }
    if case .recent(let count) = policy, count <= 1 { return false }
    touch(tag, policy: policy)
    preparedOnly.insert(tag)
    return true
  }

  /// Tabs built hidden that have not been shown yet (`prepare`). Their panels are laid out while hidden
  /// (`data-tab-prepared`), so the first frame that shows one shows it in place.
  private var preparedOnly: Set<String> = []
  func isPreparedOnly(_ tag: String) -> Bool { preparedOnly.contains(tag) }
  func didShow(_ tag: String) { preparedOnly.remove(tag) }

  /// What stands in for `tag`'s content when the tab is mounted, hidden and
  /// was built before; nil when it is to be built (the requested tab, a tab
  /// never built, or a tab view without a requested selection).
  func retainedContent(_ tag: String) -> _RenderNode? {
    guard let requested, tag != requested, let key = builtKeys[tag] else { return nil }
    // Not built this pass: when the selection falls back to it, `finishPass`
    // has the caller render once more, building it.
    mountedThisPass.remove(tag)
    return ._retainedRender(key: key)
  }

  func didBuild(_ tag: String, key: _FiberKey?) {
    builtKeys[tag] = key
  }

  /// The tabs whose screen on top asked for `toolbar(.hidden, for: .tabBar)` when they were last built. A hidden tab
  /// kept without building (`retainedContent`) has no subtree to look at, so it answers as it did then.
  private var hidingTabBar: Set<String> = []

  /// Whether `node`, the content `tag` rendered this pass, hides the tab bar while it is on screen.
  func hidesTabBar(_ tag: String, node: _RenderNode) -> Bool {
    if node._retainsRenderedSubtree { return hidingTabBar.contains(tag) }
    let hides = _requestsHiddenTabBar(node)
    if hides { hidingTabBar.insert(tag) } else { hidingTabBar.remove(tag) }
    return hides
  }

  /// Records the tab the view actually selected. Returns false when it was
  /// not built this pass (a hidden or unknown requested tag fell back to
  /// another tab), so the caller renders once more.
  func finishPass(selected: String, policy: TabViewMountPolicy) -> Bool {
    touch(selected, policy: policy)
    return mountedThisPass.contains(selected)
  }

  private func touch(_ tag: String, policy: TabViewMountPolicy) {
    if let index = order.firstIndex(of: tag) { order.remove(at: index) }
    order.append(tag)
    visited.insert(tag)
    if case .recent(let count) = policy {
      let capacity = max(1, count)
      while order.count > capacity {
        let evicted = order.removeFirst()
        visited.remove(evicted)
        builtKeys.removeValue(forKey: evicted)
        hidingTabBar.remove(evicted)
      }
    }
  }
}

final class _TabSelectionSink {
  let select: (_RuntimeValue) -> Void
  private let selectRawValue: ((String) -> Bool)?
  private var values: [String: _RuntimeValue] = .init()

  init(select: @escaping (_RuntimeValue) -> Void, selectRawValue: ((String) -> Bool)? = nil) {
    self.select = select
    self.selectRawValue = selectRawValue
  }

  func beginRegistrationPass() { values.removeAll(keepingCapacity: true) }

  /// Registers a tab's value under its tag. The last registration of a tag wins, in the order the pass renders them:
  /// a tab rendered in a deferred part of the tree registers later than plain recursion would have, so the
  /// registration is ordered by its position (`_RenderStaging.ordered`) and takes effect when the pass has settled.
  @MainActor func register<Value: Hashable>(_ value: Value) {
    let key = fiberKeyDescription(_FiberKey(value))
    let runtime = _RuntimeValue(value)
    _RenderStaging.ordered { [self] _ in values[key] = runtime }
  }

  func select(rawTag: String) {
    if selectRawValue?(rawTag) == true { return }
    if let value = values[rawTag] { select(value) }
  }
}

/// SwiftUI's tab role is intentionally small: the browser host uses the
/// semantic value to place special tabs (notably search) without exposing a
/// DOM-specific tab bar API.
public enum TabRole: Hashable, Sendable {
  case search

  /// The value written to the host's `data-tab-role` attribute.
  var _attributeValue: String {
    switch self {
    case .search: return "search"
    }
  }
}

/// The presentation styles understood by `TabView`.  The value is a small
/// semantic token rather than a renderer type: the browser stylesheet uses
/// the same declaration to choose a floating app switcher on phone viewports
/// and a persistent sidebar on iPad/Mac-sized viewports.
@MainActor @preconcurrency public protocol TabViewStyle {
  /// The browser token for a built-in style (`automatic`, `sidebar-adaptable`).
  var _swiftUIWebTabViewStyle: String { get }
}

public extension TabViewStyle {
  var _swiftUIWebTabViewStyle: String { "automatic" }
}

public nonisolated struct DefaultTabViewStyle: TabViewStyle {
  public nonisolated init() {}
  public var _swiftUIWebTabViewStyle: String { "automatic" }
}

public nonisolated struct SidebarAdaptableTabViewStyle: TabViewStyle {
  public nonisolated init() {}
  public var _swiftUIWebTabViewStyle: String { "sidebar-adaptable" }
}

public extension TabViewStyle where Self == DefaultTabViewStyle {
  @MainActor @preconcurrency static var automatic: DefaultTabViewStyle { DefaultTabViewStyle() }
}

public extension TabViewStyle where Self == SidebarAdaptableTabViewStyle {
  @MainActor @preconcurrency static var sidebarAdaptable: SidebarAdaptableTabViewStyle { SidebarAdaptableTabViewStyle() }
}

/// Persistent customization state for a TabView. The identifiers are usually
/// supplied with `.customizationID`; a tab's stable selection tag is used as a
/// fallback so dynamic tabs continue to restore their order and visibility.
public struct TabViewCustomization: Hashable, Sendable {
  package var hiddenTabs: Set<String>
  package var order: [String]

  public init() {
    self.hiddenTabs = []
    self.order = []
  }

  package init(hiddenTabs: Set<String> = [], order: [String] = []) {
    self.hiddenTabs = hiddenTabs
    self.order = order
  }

  /// Descriptive aliases retained for package callers that persist customization.
  package var hiddenTabIdentifiers: Set<String> {
    get { hiddenTabs }
    set { hiddenTabs = newValue }
  }

  package var hiddenTabIDs: Set<String> {
    get { hiddenTabs }
    set { hiddenTabs = newValue }
  }

  package var tabOrder: [String] {
    get { order }
    set { order = newValue }
  }

  /// Compact, Foundation-free persistence representation used by
  /// `@AppStorage`/`@SceneStorage`. Identifiers are escaped so customization
  /// values remain round-trippable even when an app uses `|`, `,`, or `\\` in
  /// a customization ID.
  package var _storageValue: String {
    let hidden = hiddenTabs.sorted().map(_escapeCustomizationStorage).joined(separator: ",")
    let ordered = order.map(_escapeCustomizationStorage).joined(separator: ",")
    return hidden + "|" + ordered
  }

  package init(_storageValue rawValue: String) {
    if rawValue.isEmpty || rawValue == "|" {
      hiddenTabs = []
      order = []
      return
    }
    let parts = _splitCustomizationStorage(rawValue)
    hiddenTabs = Set(parts.first?.compactMap { identifier in
      identifier.isEmpty ? nil : _unescapeCustomizationStorage(identifier)
    } ?? [])
    order = parts.dropFirst().flatMap { fields in
      fields.compactMap { identifier in
        identifier.isEmpty ? nil : _unescapeCustomizationStorage(identifier)
      }
    }
  }
}

private func _escapeCustomizationStorage(_ value: String) -> String {
  var escaped = ""
  for character in value {
    if character == "\\" || character == "," || character == "|" { escaped.append("\\") }
    escaped.append(character)
  }
  return escaped
}

private func _splitCustomizationStorage(_ value: String) -> [[String]] {
  var fields: [[String]] = [[]]
  var current = ""
  var escaping = false
  for character in value {
    if escaping {
      current.append(character)
      escaping = false
    } else if character == "\\" {
      escaping = true
    } else if character == "," {
      fields[fields.count - 1].append(current)
      current = ""
    } else if character == "|" {
      fields[fields.count - 1].append(current)
      current = ""
      fields.append([])
    } else {
      current.append(character)
    }
  }
  fields[fields.count - 1].append(current)
  return fields
}

private func _unescapeCustomizationStorage(_ value: String) -> String? {
  value
}

private struct _RenderedTab {
  let node: _RenderNode
  let tag: String
  let label: String
  let section: String?
  let role: TabRole?
  let systemImage: String?
  let badge: String?
  let customizationID: String?
  let disabled: Bool
  let sourceIndex: Int

  var customizationKey: String { customizationID ?? tag }
}

/// A SwiftUI-shaped tab container. Tagged children become an accessible
/// tablist and every panel remains mounted behind a stable keyed container;
/// inactive panels are hidden instead of removed, preserving SwiftUI state and
/// independent navigation stacks. Untagged content remains fully state-driven,
/// so existing applications can supply custom tab chrome or switch their
/// content with an ordinary `switch`.
extension TabView where SelectionValue == Int {
  /// SwiftUI's ViewBuilder spelling for tabs without a selection; the tabs
  /// show in order and keep the Int tag they were built with.
  public nonisolated init(@ViewBuilder content: () -> Content) {
    self.init(selection: nil as Binding<Int>?, content: content)
  }

  /// The concrete Int selection path. A constrained-extension overload is
  /// preferred over the generic `Binding<SelectionValue>` initializer, so
  /// Embedded builds route Int tags through this path rather than through
  /// runtime-erased selection values.
  nonisolated package init(selection: Binding<Int>?, @ViewBuilder content: () -> Content) {
    self.selection = selection
    self.content = content()
    self._internalSelectedTag = State(wrappedValue: nil)
    self.selectedTag = { selection.map { fiberKeyDescription(_FiberKey($0._readForRenderer())) } }
    self.selectTag = { raw in
      if let value = Int(raw) { selection?.wrappedValue = value }
    }
    if let selection {
      self.tabSelectionSink = _TabSelectionSink { value in
        if let value: Int = value.read() { selection.wrappedValue = value }
      }
    } else {
      self.tabSelectionSink = nil
    }
  }

  nonisolated package init(selection: Binding<Int>, @ViewBuilder content: () -> Content) {
    self.init(selection: selection as Binding<Int>?, content: content)
  }

  nonisolated package init<C>(selection: Binding<Int>, @TabContentBuilder<Int> content: () -> C)
  where Content == TabContentBuilder<Int>.Content<C>, C: TabContent {
    self.init(selection: selection as Binding<Int>?, content: { TabContentBuilder<Int>.Content(content()) })
  }
}

public nonisolated struct TabView<SelectionValue, Content>: View where SelectionValue: Hashable, Content: View {
  public typealias Body = Never
  let selection: Binding<Int>?
  let content: Content
  private let selectedTag: () -> String?
  private let selectTag: (String) -> Void
  private let tabSelectionSink: _TabSelectionSink?
  @State private var internalSelectedTag: String?
  @State(memberID: 2522378121) private var tabMount = _TabMountTracker()
  /// Advances when a tab is prepared (`_TabMountTracker.prepare`), so the tab view renders and builds it.
  @State(memberID: 2522378122) private var preparedTabs = 0

  /// SwiftUI's ViewBuilder spelling with an optional selection. Tabs are
  /// identified by the tags they register; a `nil` selection shows the first tab.
  public nonisolated init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) {
    self.selection = nil
    self.content = content()
    self._internalSelectedTag = State(wrappedValue: nil)
    guard let selection else {
      self.selectedTag = { nil }
      self.selectTag = { _ in }
      self.tabSelectionSink = nil
      return
    }
    self.selectedTag = { fiberKeyDescription(_FiberKey(selection._readForRenderer())) }
    // The sink receives the original typed tag from Tag/Tab instead of
    // reconstructing it from an HTML string. This supports enum-backed tabs
    // (the common pattern in real SwiftUI applications) without reflection.
    let sink = _TabSelectionSink(
      select: { value in
        if let value: SelectionValue = value.read() { selection.wrappedValue = value }
      },
      selectRawValue: { rawTag in
        // Embedded's runtime-erased value reader intentionally stays small;
        // the common integer spelling is served by the Int overloads below.
        if let integer = Int(rawTag), let value = integer as? SelectionValue {
          selection.wrappedValue = value
          return true
        }
        return false
      }
    )
    self.tabSelectionSink = sink
    self.selectTag = { raw in sink.select(rawTag: raw) }
  }

  /// `TabView(selection:) { Tab(...) }`: the TabContentBuilder spelling.
  public nonisolated init<C>(selection: Binding<SelectionValue>, @TabContentBuilder<SelectionValue> content: () -> C)
  where Content == TabContentBuilder<SelectionValue>.Content<C>, C: TabContent {
    self.init(selection: Optional(selection), content: { TabContentBuilder<SelectionValue>.Content(content()) })
  }

  /// `TabView { Tab(...) }` with no selection: the tabs carry `Never` values.
  public nonisolated init<C>(@TabContentBuilder<Never> content: () -> C)
  where SelectionValue == Never, Content == TabContentBuilder<Never>.Content<C>, C: TabContent {
    self.init(selection: nil as Binding<Never>?, content: { TabContentBuilder<Never>.Content(content()) })
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["tab-view"]
    let style = context.environment.tabViewStyle
    node.attributes["data-tab-style"] = style
    node.attributes["data-layout-kind"] = "inset"
    node.attributes["data-inset-edge"] = "bottom"
    node.attributes["data-layout-gap"] = "0"
    if style == "sidebar-adaptable" {
      node.attributes["data-tab-adaptive"] = "sidebar-bottom"
      // The browser host chooses mobile / rail / sidebar from these default
      // widths (≤767 mobile, 768–1199 rail, ≥1200 sidebar). An application
      // can override them in its document head with
      // <meta name="tab-breakpoints" content="720,1100">.
      node.attributes["data-tab-breakpoints"] = "767,1199"
    }
    tabSelectionSink?.beginRegistrationPass()
    // Capture the selection route once per render. Embedded closures retain
    // locals reliably; reading an optional property through a copied `self`
    // inside a later DOM event could otherwise lose the concrete Int binding
    // and fall back to runtime-erased selection.
    let hasIntegerSelection = self.selection != nil
    nonisolated(unsafe) let selectTag = self.selectTag
    nonisolated(unsafe) let selectionSink = self.tabSelectionSink
    var contentContext = context.child(_FiberKey("content"))
    contentContext.environment.tabSelectionSink = tabSelectionSink
    let tabMount = self.tabMount
    contentContext.environment.tabMount = tabMount
    _ = preparedTabs
    if let panelSize = tabMount.panelSize { contentContext.environment._geometryHint = panelSize }
    let mountPolicy = context.environment.tabViewMountPolicy
    tabMount.beginPass(requested: self.selectedTag() ?? internalSelectedTag, policy: mountPolicy)
    _RenderStaging.enterStage()
    var rendered = content._render(in: contentContext)
    _RenderStaging.exitStage()
    // The mount tracker and the selection sink learn from the tabs as they render, deferred ones included: the tab
    // view gathers them once the pass has rendered its content (see `_StagedRender`).
    nonisolated(unsafe) let view = self
    return _RenderStaging.stagedNode { stage in
      stage.whenSettled { stage in
        let customization = context.environment.tabViewCustomization
        @MainActor func finishTabs(_ stage: _StagedRender, _ ordered: [_RenderedTab], _ selectedTag: String) {
          _finishTabView(
            stage, ordered, selectedTag, rendered: rendered, node: node, context: context, customization: customization,
            style: style, tabMount: tabMount, mountPolicy: mountPolicy, hasIntegerSelection: hasIntegerSelection,
            selectTag: selectTag, selectionSink: selectionSink,
            selectInternally: { view.internalSelectedTag = $0 }, didPrepare: { view.preparedTabs &+= 1 })
        }
        // Tags now retain their exact identities before the selection is compared.
        let boundSelection = view.selectedTag()
        if let boundSelection { node.attributes["data-selected-tab"] = boundSelection }
        guard var tagged = view._collectTabs(in: rendered), !tagged.isEmpty else {
          node.children = rendered.isEmpty ? [] : [rendered]
          stage.complete(node)
          return
        }

        var ordered = view._orderedTabs(tagged, customization: customization)
        let boundTag = boundSelection
        let requestedTag = boundTag ?? internalSelectedTag
        let selectedTag = requestedTag.flatMap { requested in
          ordered.contains(where: { $0.tag == requested && !view._isHidden($0, customization: customization) })
            ? requested
            : nil
        }
          ?? ordered.first(where: { !view._isHidden($0, customization: customization) })?.tag
          ?? ordered[0].tag
        node.attributes["data-selected-tab"] = selectedTag
        if !tabMount.finishPass(selected: selectedTag, policy: mountPolicy) {
          // The selection fell back to a tab that was not built (its requested
          // tag was hidden or unknown): build it now.
          tabMount.beginPass(requested: selectedTag, policy: mountPolicy)
          _RenderStaging.enterStage()
          rendered = content._render(in: contentContext)
          _RenderStaging.exitStage()
          stage.whenSettled { stage in
            if let again = view._collectTabs(in: rendered), !again.isEmpty {
              tagged = again
              ordered = view._orderedTabs(again, customization: customization)
            }
            _ = tabMount.finishPass(selected: selectedTag, policy: mountPolicy)
            finishTabs(stage, ordered, selectedTag)
          }
          return
        }
        finishTabs(stage, ordered, selectedTag)
      }
    }
  }

  private func _collectTabs(in node: _RenderNode) -> [_RenderedTab]? { _collectRenderedTabs(in: node) }

  private func _orderedTabs(_ tabs: [_RenderedTab], customization: TabViewCustomization) -> [_RenderedTab] {
    _orderedRenderedTabs(tabs, customization: customization)
  }

  private func _isHidden(_ tab: _RenderedTab, customization: TabViewCustomization) -> Bool {
    _tabIsHidden(tab, customization: customization)
  }
}

// The tab collection of `TabView`, out of the generic type so it is compiled once rather than once per tab view type.
private func _collectRenderedTabs(in node: _RenderNode, section: String? = nil, into result: inout [_RenderedTab]) {
  if let tag = node.attributes["data-tag"] {
    let role: TabRole? = node.attributes["data-tab-role"] == TabRole.search._attributeValue ? .search : nil
    let disabled = node.attributes["disabled"] == "disabled" || node.attributes["aria-disabled"] == "true"
    result.append(_RenderedTab(
      node: node,
      tag: tag,
      label: node.attributes["data-tab-label"] ?? "",
      section: section,
      role: role,
      systemImage: node.attributes["data-tab-system-image"],
      badge: node.attributes["data-badge"],
      customizationID: node.attributes["data-tab-customization-id"],
      disabled: disabled,
      sourceIndex: result.count
    ))
    return
  }
  let nextSection = node.attributes["data-tab-section-title"] ?? section
  for child in node.children {
    if child.attributes["data-tab-section-header"] == "true" { continue }
    _collectRenderedTabs(in: child, section: nextSection, into: &result)
  }
}

private func _collectRenderedTabs(in node: _RenderNode) -> [_RenderedTab]? {
  var result: [_RenderedTab] = []
  _collectRenderedTabs(in: node, into: &result)
  return result.isEmpty ? nil : result
}

private func _orderedRenderedTabs(_ tabs: [_RenderedTab], customization: TabViewCustomization) -> [_RenderedTab] {
  guard !customization.order.isEmpty else { return tabs }
  // The order can come from storage another script wrote: a repeated tab keeps its first position instead of trapping.
  let positions = Dictionary(customization.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
  return tabs.enumerated().sorted {
    let lhs = positions[$0.element.customizationKey] ?? Int.max
    let rhs = positions[$1.element.customizationKey] ?? Int.max
    return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
  }.map { $0.element }
}

private func _tabIsHidden(_ tab: _RenderedTab, customization: TabViewCustomization) -> Bool {
  customization.hiddenTabs.contains(tab.customizationKey) || customization.hiddenTabs.contains(tab.tag)
}

/// Retires the owners of `node`'s subtree that no tab node holds: what a tab view rendered only to read it.
@MainActor private func _retireOwnersAboveTabs(in node: _RenderNode, registry: _RenderOwnerRegistry?) {
  guard let registry else { return }
  var pending = [node]
  while let current = pending.popLast() {
    if current.attributes["data-tag"] != nil { continue }
    if let token = current._renderOwnerToken { registry._remove(token) }
    pending.append(contentsOf: current.children)
  }
}

/// The tab bar and the panels of a `TabView` once its tabs have rendered (the end of `TabView._render`). Out of the
/// generic type so it is compiled once, not once per tab view type; `selectInternally` and `didPrepare` write the tab
/// view's own state (its internal selection, its count of prepared tabs).
@MainActor private func _finishTabView(
  _ stage: _StagedRender, _ ordered: [_RenderedTab], _ selectedTag: String, rendered: _RenderNode, node: _RenderNode,
  context: _RenderContext, customization: TabViewCustomization, style: String, tabMount: _TabMountTracker,
  mountPolicy: TabViewMountPolicy, hasIntegerSelection: Bool, selectTag: @escaping (String) -> Void,
  selectionSink: _TabSelectionSink?, selectInternally: @escaping @MainActor (String) -> Void,
  didPrepare: @escaping @MainActor () -> Void
) {
  // Only the tabs' own nodes are mounted (in the panels below): the sections around them and their headers
  // were rendered for their titles, and their owners would stay registered for good, a section's every pass.
  _retireOwnersAboveTabs(in: rendered, registry: context._renderOwnerRegistry)
  if !customization.hiddenTabs.isEmpty || !customization.order.isEmpty {
    node.attributes["data-tab-customization"] = "true"
  }

  let namespace = context._fiberPath.description + "#tabview"
  // The text of a nested tab view's path is as long as its depth, and every identifier below hashes it
  // again with its tag: hash it once, and continue from that state for each tag.
  let namespaceHash = _tabStableHashState(namespace)
  if let history = context.environment.navigationHistory {
    history._setTabDefault(namespace: namespace, tag: selectedTag)
    history._observeTab(namespace: namespace) { rawTag in
      if let sink = selectionSink {
        sink.select(rawTag: rawTag)
      } else {
        selectInternally(rawTag)
      }
    }
  }

  let contentNode = _RenderNode.element("div")
  contentNode.key = _FiberKey("__tab_content")
  contentNode.classes = ["tab-body"]
  contentNode.attributes["data-tab-content"] = "true"
  // Measured like an `onGeometryChange`, for the tabs built later (`_TabMountTracker.panelSize`). Nothing
  // renders again when it changes: the tabs on screen have their own measurements.
  contentNode.attributes["data-geometry-change"] = "1"
  contentNode.events["geometryChange"] = _EventHandler(name: "geometryChange", action: { rawValue in
    guard let measurement = _GeometryMeasurement(decoding: rawValue), measurement.size.width > 0, measurement.size.height > 0 else { return }
    tabMount.panelSize = measurement.size
  })
  for tab in ordered {
    let panel = _RenderNode.element("div")
    panel.key = _FiberKey("__tab_panel_\(tab.tag)")
    panel.classes = ["tab-panel"]
    let panelID = _tabDOMIdentifier(namespaceHash: namespaceHash, tag: tab.tag)
    panel.attributes["id"] = panelID
    panel.attributes["data-tab-panel"] = "true"
    panel.attributes["role"] = "tabpanel"
    panel.attributes["data-tab-value"] = tab.tag
    panel.attributes["data-tab-key"] = tab.customizationKey
    panel.attributes["data-tab-preserve-state"] = "true"
    panel.attributes["aria-labelledby"] = _tabDOMIdentifier(namespaceHash: namespaceHash, tag: tab.tag + "|button")
    let isSelected = tab.tag == selectedTag
    panel.attributes["data-tab-hidden"] = isSelected ? "false" : "true"
    if isSelected {
      tabMount.didShow(tab.tag)
    } else if tabMount.isPreparedOnly(tab.tag) {
      panel.attributes["data-tab-prepared"] = "true"
    } else if !tabMount.isPrepared(tab.tag) {
      // A tab never built holds only its placeholder: the host keeps the panel on screen when its button is
      // clicked, until the publication that builds it arrives, instead of showing it empty.
      panel.attributes["data-tab-unbuilt"] = "true"
    }
    // A hidden tab whose screen hides the tab bar is not shown by the host on its own either: the bar goes with
    // the publication that selects the tab, and the screen comes with it rather than a frame before.
    if !isSelected, tabMount.hidesTabBar(tab.tag, node: tab.node) {
      panel.attributes["data-tab-hides-bar"] = "true"
    }
    panel.attributes["aria-hidden"] = isSelected ? "false" : "true"
    panel.children = [tab.node]
    contentNode.children.append(panel)
  }

  // `toolbar(.hidden, for: .tabBar)` on a view that is on screen (the selected tab, or the destination a
  // NavigationStack shows inside it) removes the tab bar while that view is shown, as in SwiftUI.
  if let selected = ordered.first(where: { $0.tag == selectedTag }), tabMount.hidesTabBar(selected.tag, node: selected.node) {
    node.attributes["data-tab-bar-hidden"] = "true"
    node.children = [contentNode]
    stage.complete(node)
    return
  }

  let tabBar = _RenderNode.element("div")
  tabBar.classes = ["tab-list"]
  tabBar.attributes["role"] = "tablist"
  tabBar.attributes["id"] = _tabDOMIdentifier(namespaceHash: namespaceHash, tag: "tab-list")
  tabBar.attributes["data-tab-responsive"] = "mobile-floating-apps-tablet-rail-desktop-sidebar"
  if style == "sidebar-adaptable" { tabBar.classes.append("tab-sidebar-list") }
  var previousSection: String?
  var buttonIndex = 0
  for tab in ordered where !_tabIsHidden(tab, customization: customization) {
    if tab.section != previousSection, let section = tab.section {
      let header = _RenderNode.element("span")
      header.classes = ["tab-section-header"]
      header.attributes["role"] = "presentation"
      header.attributes["data-tab-section"] = section
      header.attributes["data-tab-section-title"] = section
      header.children = [.text(section)]
      tabBar.children.append(header)
    }
    previousSection = tab.section

    let button = _RenderNode.element("button")
    button.key = _FiberKey("__tab_button_\(tab.tag)")
    button.attributes["type"] = "button"
    button.attributes["role"] = "tab"
    button.attributes["id"] = _tabDOMIdentifier(namespaceHash: namespaceHash, tag: tab.tag + "|button")
    button.attributes["aria-selected"] = tab.tag == selectedTag ? "true" : "false"
    button.attributes["aria-controls"] = _tabDOMIdentifier(namespaceHash: namespaceHash, tag: tab.tag)
    button.attributes["data-tab-index"] = "\(buttonIndex)"
    button.attributes["data-tab-value"] = tab.tag
    button.attributes["data-tab-role"] = tab.role?._attributeValue ?? "automatic"
    if let systemImage = tab.systemImage { button.attributes["data-tab-system-image"] = systemImage }
    button.attributes["data-tab-has-icon"] = tab.systemImage == nil ? "false" : "true"
    if tab.disabled {
      button.attributes["disabled"] = "disabled"
      button.attributes["aria-disabled"] = "true"
    }
    let label = tab.label.isEmpty ? tab.tag : tab.label
    button.attributes["data-tab-label"] = label
    button.attributes["aria-label"] = label
    if tab.systemImage == nil {
      button.attributes["data-tab-fallback"] = label.first.map(String.init) ?? "•"
    }
    button.attributes["tabindex"] = tab.tag == selectedTag ? "0" : "-1"
    // The page asks for a tab the pointer rests on (`tabPrepare`), which is built hidden before it is selected.
    if !tab.disabled, tab.tag != selectedTag, !tabMount.isPrepared(tab.tag) {
      let tag = tab.tag
      button.attributes["data-tab-prepare"] = "true"
      button.events["tabPrepare"] = _EventHandler(name: "tabPrepare", action: {
        if tabMount.prepare(tag, policy: mountPolicy) { didPrepare() }
      })
    }
    button.children = []
    if let systemImage = tab.systemImage {
      let icon = _RenderNode.element("span")
      icon.classes = ["tab-icon", "symbol-icon"]
      icon.attributes["data-symbol"] = systemImage
      icon.attributes["data-tab-fallback"] = (tab.label.isEmpty ? tab.tag : tab.label).first.map(String.init) ?? "•"
      icon.attributes["aria-hidden"] = "true"
      button.children.append(icon)
    }
    let titleNode = _RenderNode.element("span")
    titleNode.classes = ["tab-title"]
    titleNode.children = [.text(label)]
    button.children.append(titleNode)
    if let badge = tab.badge, !badge.isEmpty {
      button.children.append(_tabBadgeNode(badge))
      button.attributes["data-badge"] = badge
      if _isTabActivityBadge(badge) { button.attributes["data-badge-style"] = "dot" }
    }
    if !tab.disabled {
      if let handler = tab.node.events["tab-select"] {
        button.events["click"] = _EventHandler(name: "click", action: {
          // The Int overload stores a concrete Binding in `selection`.
          // Apply that binding directly instead of routing through the
          // retained content event: this keeps the browser event path
          // identical to native TabView and avoids a stale semantic
          // snapshot when the content closure has already been retained.
          if hasIntegerSelection {
            selectTag(tab.tag)
          } else if let selectionSink {
            selectionSink.select(rawTag: tab.tag)
          } else {
            handler.action()
          }
          if tab.tag != selectedTag {
            historyUpdateTab(context: context, namespace: namespace, tag: tab.tag)
          }
        })
      } else {
        button.events["click"] = _EventHandler(name: "click", action: {
          if hasIntegerSelection { selectTag(tab.tag) }
          else if let selectionSink { selectionSink.select(rawTag: tab.tag) }
          else { selectInternally(tab.tag) }
          if tab.tag != selectedTag {
            historyUpdateTab(context: context, namespace: namespace, tag: tab.tag)
          }
        })
      }
    }
    tabBar.children.append(button)
    buttonIndex += 1
  }
  if style == "sidebar-adaptable" {
    let visibleBadges = ordered.filter { !_tabIsHidden($0, customization: customization) }.compactMap { $0.badge }
    node.children = [contentNode] + _adaptiveTabChrome(
      tabBar: tabBar,
      sidebarID: _tabDOMIdentifier(namespaceHash: namespaceHash, tag: "sidebar"),
      badges: visibleBadges
    )
  } else {
    // iOS 26's tab bar floats: a capsule inset from the screen edges. The layout owns the row the bar sits in
    // (`.tab-bar`, the inset of the tab view) and sizes it to the page; the capsule inside (`.tab-list`) is
    // free to be narrower than the row and centered in it.
    let dock = _RenderNode.element("div")
    dock.classes = ["tab-bar"]
    dock.children = [tabBar]
    node.children = [contentNode, dock]
  }
  stage.complete(node)
}

@MainActor private func historyUpdateTab(context: _RenderContext, namespace: String, tag: String) {
  guard let history = context.environment.navigationHistory else { return }
  history._updateTab(namespace: namespace, tag: tag)
}

/// `tab-item-` and the FNV-1a hash of `namespace|tag`, continued from the state `namespaceHash` the hash of
/// `namespace` left.
private func _tabDOMIdentifier(namespaceHash: UInt64, tag: String) -> String {
  var hash = namespaceHash
  hash ^= UInt64(UInt8(ascii: "|"))
  hash &*= 1099511628211
  for byte in tag.utf8 {
    hash ^= UInt64(byte)
    hash &*= 1099511628211
  }
  return "tab-item-\(String(hash, radix: 16))"
}

/// FNV-1a over the UTF-8 bytes. A nested tab view's namespace is as long as its depth, so this walks the contiguous
/// bytes instead of stepping the UTF-8 view.
private func _tabStableHashState(_ value: String) -> UInt64 {
  var hash: UInt64 = 1469598103934665603
  var text = value
  text.withUTF8 { bytes in
    for byte in bytes {
      hash ^= UInt64(byte)
      hash &*= 1099511628211
    }
  }
  return hash
}

/// SwiftUI's modern tab declaration.  `TabView` remains responsible for
/// selection and tab chrome; this view only contributes a stable tag, label,
/// and content subtree so both the modern and legacy spellings share one
/// Fiber implementation.
public struct Tab<Value, Content, Label> {
  public typealias Body = Never
  /// `nil` for an untagged tab (SwiftUI's `Tab` without a `value`, which only a `TabView` without a selection accepts).
  let value: Value?
  let content: Content
  let label: Label
  let role: TabRole?
  let systemImage: String?

  public nonisolated init<S: StringProtocol>(_ title: S, systemImage: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content) where Label == Text {
    self.value = value; self.content = content(); self.label = Text(String(title)); self.role = role; self.systemImage = systemImage
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content) where Label == Text { self.init(titleKey.resolved, systemImage: systemImage, value: value, role: role, content: content) }

  /// SwiftUI permits a value/role tab whose label is supplied later by
  /// `.tabItem`. Keep that spelling source-compatible; the tab-item modifier
  /// provides the visible label when present.
  /// Apple's value-only tab spellings: `Tab(value:role:content:)` labels its tab with a
  /// text label, `Tab(value:content:)` has no label. A label is supplied later with `.tabItem`.
  public nonisolated init(value: Value, role: TabRole?, @ViewBuilder content: () -> Content) where Label == Text {
    self.value = value; self.content = content(); self.label = Text(""); self.role = role; self.systemImage = nil
  }

  public nonisolated init(value: Value, @ViewBuilder content: () -> Content) where Label == EmptyView {
    self.value = value; self.content = content(); self.label = EmptyView(); self.role = nil; self.systemImage = nil
  }

  public nonisolated init(value: Value, role: TabRole?, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.value = value; self.content = content(); self.label = label(); self.role = role; self.systemImage = nil
  }

  public nonisolated init(value: Value, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.value = value; self.content = content(); self.label = label(); self.role = nil; self.systemImage = nil
  }
}

extension Tab: TabContent where Value: Hashable, Content: View, Label: View {
  public typealias TabValue = Value

  @_spi(Renderer) @MainActor public func _renderTabContent(in context: _RenderContext) -> _RenderNode {
    // Include the value in the semantic render path so a dynamic ForEach of
    // Tabs can reorder without moving the state owned by its content. An
    // untagged tab is identified by its title and selects through TabView's state.
    let tagIdentity = value.map { _FiberKey($0) } ?? _FiberKey("__untagged_\(_tabLabelText(label))")
    let tag = fiberKeyDescription(tagIdentity)
    let tabMount = context.environment.tabMount
    let mounted = tabMount?.shouldMount(tag) ?? true
    // A hidden tab already built keeps what the Fiber holds for it (see `_TabMountTracker`).
    let retained = mounted ? tabMount?.retainedContent(tag) : nil
    let built = mounted && retained == nil
    let node: _RenderNode
    if let retained {
      node = retained
    } else if built {
      // The content's `@State` resolves in a scope of its own, as a `ForEach` tab's does: keyed by this tab's path
      // whichever other tabs the pass builds. In the tab view's scope its slot followed the tabs built before it, so
      // a tab kept without building would hand its state to the next one.
      let contentContext = context.child(tagIdentity).child(_FiberKey("content"))
      let saved = _enterRenderScope(contentContext, viewTag: "tab-content")
      node = content._render(in: contentContext)
      _exitRenderScope(saved)
    } else {
      node = _RenderNode.element("div")
    }
    let labelNode = label._render(in: context.child(tagIdentity).child(_FiberKey("label")))
    let labelText = _tabLabelText(labelNode)
    let systemImage = systemImage ?? _tabLabelSystemImage(labelNode)
    let role = self.role
    let value = self.value
    let environment = context.environment
    // The tab's content may be a node that stands in for a render that has not run: what the tab says about itself is
    // written to it when it has (and the tab view reads the tabs once the pass has settled).
    let describe: @MainActor (_RenderNode) -> Void = { node in
      _renderRegistersWithAncestors()
      if built { tabMount?.didBuild(tag, key: node.key) }
      node._tagIdentity = tagIdentity
      node.attributes["data-tag"] = tag
      node.attributes["data-tab-label"] = labelText
      node.attributes["data-tab-modern"] = "true"
      node.attributes["data-tab"] = "true"
      node.attributes["data-tab-role"] = role?._attributeValue ?? "automatic"
      if let systemImage {
        node.attributes["data-tab-system-image"] = systemImage
      }
      if !environment.isEnabled {
        node.attributes["disabled"] = "disabled"
        node.attributes["aria-disabled"] = "true"
      }
      if let value, let sink = environment.tabSelectionSink {
        _renderRegistersWithAncestors()
        sink.register(value)
        node.events["tab-select"] = _EventHandler(name: "tab-select", action: { sink.select(_RuntimeValue(value)) })
      }
    }
    if node._isPendingRender {
      node._keep(.apply(_CapturedThreadState.capture(), describe))
    } else {
      describe(node)
    }
    return node
  }
}

/// SwiftUI's untagged `Tab`: the iOS 18 declaration inside a `TabView` without a selection.
public extension Tab where Value == Never {
  @_disfavoredOverload nonisolated init<S: StringProtocol>(_ title: S, systemImage: String, role: TabRole? = nil, @ViewBuilder content: () -> Content) where Label == Text {
    self.value = nil; self.content = content(); self.label = Text(String(title)); self.role = role; self.systemImage = systemImage
  }
  nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, role: TabRole? = nil, @ViewBuilder content: () -> Content) where Label == Text {
    self.init(titleKey.resolved, systemImage: systemImage, role: role, content: content)
  }
  /// An untagged tab with no label, as Apple's `Tab(content:)`.
  nonisolated init(@ViewBuilder content: () -> Content) where Label == EmptyView {
    self.value = nil; self.content = content(); self.label = EmptyView(); self.role = nil; self.systemImage = nil
  }

  /// A role-only tab has no selection value. Search gets SwiftUI's title and magnifying glass.
  nonisolated init(role: TabRole?, @ViewBuilder content: () -> Content) where Label == Text {
    self.value = nil; self.content = content(); self.label = Text(role == .search ? "Search" : "Tab"); self.role = role
    self.systemImage = role == .search ? "magnifyingglass" : nil
  }
  nonisolated init(role: TabRole?, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.value = nil; self.content = content(); self.label = label(); self.role = role; self.systemImage = nil
  }
}

/// Apple's optional-value tab declarations (`Value == T?`). The tab is tagged
/// with `Optional(value)`, so selecting it sets an optional binding to
/// `.some(value)`, and the same `TabView(selection:)` accepts both forms.
/// The `image:` spellings are not declared: SwiftUIWeb has no named image assets.
/// The StringProtocol spellings are `@_disfavoredOverload`: without it the solver
/// fails on `TabView(selection: .constant("x"))` with literal tags (Apple accepts it).
public extension Tab where Label == Text {
  @_disfavoredOverload nonisolated init<S: StringProtocol, T: Hashable>(_ title: S, systemImage: String, value: T, @ViewBuilder content: () -> Content)
  where Value == T? {
    self.init(optionalValue: value, title: String(title), systemImage: systemImage, role: nil, content: content())
  }

  @_disfavoredOverload nonisolated init<S: StringProtocol, T: Hashable>(_ title: S, systemImage: String, value: T, role: TabRole?, @ViewBuilder content: () -> Content)
  where Value == T? {
    self.init(optionalValue: value, title: String(title), systemImage: systemImage, role: role, content: content())
  }

  nonisolated init<T: Hashable>(_ titleKey: LocalizedStringKey, systemImage: String, value: T, @ViewBuilder content: () -> Content)
  where Value == T? {
    self.init(optionalValue: value, title: titleKey.resolved, systemImage: systemImage, role: nil, content: content())
  }

  nonisolated init<T: Hashable>(_ titleKey: LocalizedStringKey, systemImage: String, value: T, role: TabRole?, @ViewBuilder content: () -> Content)
  where Value == T? {
    self.init(optionalValue: value, title: titleKey.resolved, systemImage: systemImage, role: role, content: content())
  }

  nonisolated init<T: Hashable>(value: T, role: TabRole?, @ViewBuilder content: () -> Content)
  where Value == T? {
    self.init(optionalValue: value, title: "", systemImage: nil, role: role, content: content())
  }

  /// Shared storage for the optional-value spellings above.
  private nonisolated init<T: Hashable>(optionalValue tag: T, title: String, systemImage: String?, role: TabRole?, content: Content)
  where Value == T? {
    self.value = Optional(Optional(tag))
    self.content = content
    self.label = Text(title)
    self.role = role
    self.systemImage = systemImage
  }
}

public extension Tab where Label == EmptyView {
  nonisolated init<T: Hashable>(value: T, @ViewBuilder content: () -> Content) where Value == T? {
    self.value = Optional(Optional(value))
    self.content = content()
    self.label = EmptyView()
    self.role = nil
    self.systemImage = nil
  }
}

public extension Tab {
  nonisolated init<T: Hashable>(value: T, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label)
  where Value == T? {
    self.value = Optional(Optional(value))
    self.content = content()
    self.label = label()
    self.role = nil
    self.systemImage = nil
  }

  nonisolated init<T: Hashable>(value: T, role: TabRole?, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label)
  where Value == T? {
    self.value = Optional(Optional(value))
    self.content = content()
    self.label = label()
    self.role = role
    self.systemImage = nil
  }
}

/// A group of tabs with a section header. TabView flattens the contained tabs
/// into one accessible tablist while retaining the section marker for desktop
/// and compact responsive tab bars. Apple's `TabSection<Header, Content, Footer, SelectionValue>`;
/// sections have no footer in SwiftUIWeb, so `Footer` is only ever `EmptyView`.
public struct TabSection<Header, Content, Footer, SelectionValue> {
  public typealias Body = Never
  let header: Header
  let content: Content
}

extension TabSection: TabContent where Header: View, Content: TabContent, Footer: View, SelectionValue == Content.TabValue {
  public typealias TabValue = Content.TabValue

  @_spi(Renderer) @MainActor public func _renderTabContent(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("section")
    node.classes = ["tab-section"]
    let title = _tabLabelText(header)
    let sectionKey = title.isEmpty ? "untitled" : title
    let headerNode = header._render(in: context.child(_FiberKey("__tab_section_\(sectionKey)_header")))
    headerNode.attributes["data-tab-section-header"] = "true"
    if !title.isEmpty { node.attributes["data-tab-section-title"] = title }
    let contentNode = content._renderTabContent(in: context.child(_FiberKey("__tab_section_\(sectionKey)_content")))
    node.key = _FiberKey("__tab_section_\(sectionKey)")
    node.children = [headerNode]
    if !contentNode.isEmpty { node.children.append(contentNode) }
    return node
  }
}

extension TabSection where Content: TabContent, SelectionValue: Hashable {
  public init(@TabContentBuilder<SelectionValue> content: () -> Content, @ViewBuilder header: () -> Header)
  where Header: View, Footer == EmptyView {
    self.content = content()
    self.header = header()
  }

  public init(@TabContentBuilder<SelectionValue> content: () -> Content) where Header == EmptyView, Footer == EmptyView {
    self.content = content()
    self.header = EmptyView()
  }

  @_disfavoredOverload public init<S: StringProtocol>(_ title: S, @TabContentBuilder<SelectionValue> content: () -> Content)
  where Header == Text, Footer == EmptyView {
    self.content = content()
    self.header = Text(LocalizedStringKey(String(title)).resolved)
  }

  public init(_ titleKey: LocalizedStringKey, @TabContentBuilder<SelectionValue> content: () -> Content)
  where Header == Text, Footer == EmptyView {
    self.init(titleKey.resolved, content: content)
  }
}

/// Apple's optional-selection sections (`SelectionValue == V?`): their tabs are tagged
/// with optional values, as `Tab`'s optional-value spellings are.
extension TabSection where Content: TabContent {
  @_disfavoredOverload public init<V: Hashable>(@TabContentBuilder<SelectionValue> content: () -> Content, @ViewBuilder header: () -> Header)
  where Header: View, Footer == EmptyView, SelectionValue == V? {
    self.content = content()
    self.header = header()
  }

  @_disfavoredOverload public init<V: Hashable>(@TabContentBuilder<SelectionValue> content: () -> Content)
  where Header == EmptyView, Footer == EmptyView, SelectionValue == V? {
    self.content = content()
    self.header = EmptyView()
  }

  @_disfavoredOverload public init<V: Hashable, S: StringProtocol>(_ title: S, @TabContentBuilder<SelectionValue> content: () -> Content)
  where Header == Text, Footer == EmptyView, SelectionValue == V? {
    self.content = content()
    self.header = Text(LocalizedStringKey(String(title)).resolved)
  }

  public init<V: Hashable>(_ titleKey: LocalizedStringKey, @TabContentBuilder<SelectionValue> content: () -> Content)
  where Header == Text, Footer == EmptyView, SelectionValue == V? {
    self.content = content()
    self.header = Text(titleKey.resolved)
  }
}

@MainActor private func _tabLabelText<Label: View>(_ label: Label) -> String {
  let node = label._render(in: _RenderContext())
  return _tabLabelText(node)
}

private func _tabLabelText(_ node: _RenderNode) -> String {
  if let text = node.text { return text }
  if !node.children.isEmpty {
    // A label's icon draws its own fallback glyph as text; that glyph is not part of the title.
    let text = node.children.filter { $0.attributes["data-symbol"] == nil }.compactMap { child -> String? in
      if let value = child.text { return value }
      return child.children.filter { $0.attributes["data-symbol"] == nil }.compactMap { $0.text }.joined()
    }.joined(separator: " ")
    if !text.isEmpty { return text }
  }
  return node.attributes["aria-label"] ?? "Tab"
}

private func _tabLabelSystemImage(_ node: _RenderNode) -> String? {
  if let symbol = node.attributes["data-symbol"] { return symbol }
  for child in node.children {
    if let symbol = _tabLabelSystemImage(child) { return symbol }
  }
  return nil
}

/// Emits semantic compact and regular branches. A browser stylesheet or
/// adapter chooses the visible branch with media-query information.
nonisolated struct ResponsiveView<Compact: View, Regular: View>: View {
  public typealias Body = Never
  let compact: Compact
  let regular: Regular
  public init(@ViewBuilder compact: () -> Compact, @ViewBuilder regular: () -> Regular) {
    self.compact = compact()
    self.regular = regular()
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["responsive-switch"]
    node.attributes["data-responsive"] = "compact-regular"
    // Both branches share the same viewport proposal. The browser stylesheet
    // selects the visible branch, while the semantic layout engine must still
    // size the responsive container from the parent proposal instead of
    // measuring whichever branch happens to be visible in its probe DOM.
    node.attributes["data-layout-kind"] = "zstack"
    let compactNode = _RenderNode.element("div")
    compactNode.classes = ["responsive-compact"]
    compactNode.attributes["data-layout-kind"] = "zstack"
    compactNode.children = [compact._render(in: context.child(_FiberKey("compact")))]
    let regularNode = _RenderNode.element("div")
    regularNode.classes = ["responsive-regular"]
    regularNode.attributes["data-layout-kind"] = "zstack"
    regularNode.children = [regular._render(in: context.child(_FiberKey("regular")))]
    node.children = [compactNode, regularNode]
    return node
  }
}

/// Legacy SwiftUI spelling. It uses the same navigation runtime as
/// NavigationStack and is laid out as one (its bar, title and pushed screens), keeping its own class besides
/// `navigation-stack` for existing styles.
public nonisolated struct NavigationView<Content: View>: View {
  public typealias Body = Never
  let content: Content
  public nonisolated init(@ViewBuilder content: () -> Content) { self.content = content() }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let stackNode = NavigationStack { content }._render(in: context)
    stackNode.kind = .element("main")
    stackNode.classes = ["navigation-stack", "navigation-view"]
    return stackNode
  }
}

/// Visibility for the columns of a `NavigationSplitView`. The value mirrors
/// SwiftUI's public spelling and is also emitted as neutral metadata so a
/// browser stylesheet can collapse columns at narrow widths.
public enum NavigationSplitViewVisibility: Hashable, Sendable {
  case automatic
  case all
  case doubleColumn
  case detailOnly

  /// The value written to the host's `data-column-visibility` attribute.
  var _attributeValue: String {
    switch self {
    case .automatic: return "automatic"
    case .all: return "all"
    case .doubleColumn: return "doubleColumn"
    case .detailOnly: return "detailOnly"
    }
  }
}

/// A two- or three-column navigation container. It intentionally leaves
/// selection and routing to the child SwiftUI views while providing semantic
/// column landmarks and responsive visibility metadata to the HTML host.
public nonisolated struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View {
  public typealias Body = Never
  let sidebar: Sidebar
  let content: Content
  let detail: Detail
  private let columnVisibility: Binding<NavigationSplitViewVisibility>?

  public nonisolated init(
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder content: () -> Content,
    @ViewBuilder detail: () -> Detail
  ) {
    self.sidebar = sidebar()
    self.content = content()
    self.detail = detail()
    columnVisibility = nil
  }

  public nonisolated init(
    columnVisibility: Binding<NavigationSplitViewVisibility>,
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder content: () -> Content,
    @ViewBuilder detail: () -> Detail
  ) {
    self.sidebar = sidebar()
    self.content = content()
    self.detail = detail()
    self.columnVisibility = columnVisibility
  }

  public nonisolated init(
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder detail: () -> Detail
  ) where Content == EmptyView {
    self.sidebar = sidebar()
    self.content = EmptyView()
    self.detail = detail()
    columnVisibility = nil
  }

  public nonisolated init(
    columnVisibility: Binding<NavigationSplitViewVisibility>,
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder detail: () -> Detail
  ) where Content == EmptyView {
    self.sidebar = sidebar()
    self.content = EmptyView()
    self.detail = detail()
    self.columnVisibility = columnVisibility
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let visibility = columnVisibility?.wrappedValue ?? .automatic
    let node = _RenderNode.element("div")
    node.classes = ["navigation-split-view"]
    // NavigationSplitView is a proposal-driven CSS grid container. Mark the
    // host as flexible so Embedded forwards the viewport proposal while its
    // columns remain laid out by the grid instead of being absolutely placed
    // as navigation-stack destinations.
    node.attributes["data-layout-kind"] = "flexible"
    node.attributes["data-column-visibility"] = visibility._attributeValue
    node.attributes["data-column-count"] = Content.self == EmptyView.self ? "2" : "3"

    let sidebarNode = column("sidebar", role: "complementary", sidebar, context: context)
    let contentNode = column("content", role: "region", content, context: context)
    let detailNode = column("detail", role: "main", detail, context: context)

    if Content.self == EmptyView.self {
      node.children = [sidebarNode, detailNode]
    } else {
      node.children = [sidebarNode, contentNode, detailNode]
    }
    // `navigationSplitViewColumnWidth` on a column's content sizes that column's track.
    var tracks: [String] = []
    var sized = false
    for (index, column) in node.children.enumerated() {
      let hints = column.children.first?.attributes ?? .init()
      if let ideal = hints["data-column-width-ideal"] {
        let low = hints["data-column-width-min"] ?? ideal
        let high = hints["data-column-width-max"] ?? ideal
        tracks.append("minmax(\(low)px, \(high)px)")
        sized = true
      } else {
        tracks.append(index == node.children.count - 1 ? "minmax(0, 1fr)" : "minmax(180px, \(index == 0 && node.children.count == 3 ? 240 : 280)px)")
      }
    }
    if sized { node.styles["grid-template-columns"] = tracks.joined(separator: " ") }
    applyVisibility(visibility, to: node.children)
    return node
  }

  @MainActor private func column<Column: View>(
    _ name: String,
    role: String,
    _ content: Column,
    context: _RenderContext
  ) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["navigation-column", "navigation-\(name)"]
    node.attributes["data-navigation-column"] = name
    node.attributes["role"] = role
    let rendered = content._render(in: context.child(_FiberKey(name)))
    node.children = rendered.isEmpty ? [] : [rendered]
    if name == "detail" {
      // Shown only in a compact viewport, where the detail replaces the sidebar; the host handles the tap.
      let back = _RenderNode.element("button")
      back.classes = ["compact-back"]
      back.attributes["data-compact-back"] = "true"
      back.attributes["type"] = "button"
      back.attributes["aria-label"] = "Back"
      back.children = [.text("‹ Back")]
      node.children.insert(back, at: 0)
    }
    return node
  }

  private func applyVisibility(_ visibility: NavigationSplitViewVisibility, to columns: [_RenderNode]) {
    switch visibility {
    case .automatic, .all: break
    case .doubleColumn:
      if columns.count == 3 { columns[1].attributes["data-column-hidden"] = "true" }
    case .detailOnly:
      for column in columns.dropLast() { column.attributes["data-column-hidden"] = "true" }
    }
  }
}

public extension View {
  /// The width of a `NavigationSplitView` column. The column the modified view belongs to gets that width (or a
  /// range for the layout to choose from); the host does not let the user resize it.
  nonisolated func navigationSplitViewColumnWidth(_ width: CGFloat) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    navigationSplitViewColumnWidth(min: width, ideal: width, max: width)
  }

  nonisolated func navigationSplitViewColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    var attributes: _NodeValues = ["data-column-width-ideal": _layoutNumber(Double(ideal))]
    if let min { attributes["data-column-width-min"] = _layoutNumber(Double(min)) }
    if let max { attributes["data-column-width-max"] = _layoutNumber(Double(max)) }
    return modifier(_SemanticCompatibilityModifier(attributes: attributes))
  }
}

public nonisolated struct NavigationLink<Label: View, Destination: View>: View {
  public typealias Body = Never
  let destination: Destination
  let label: Label
  private let activation: (@MainActor (NavigationContext) -> Void)?
  private let activeRegistration: (@MainActor (NavigationContext) -> Void)?
  private let navigationKey: _FiberKey?
  /// The link's value, so a `List(selection:)` can select it instead of pushing it.
  private var selectionValue: _RuntimeValue?

 nonisolated public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
    self.init(destination: destination(), label: label)
  }
  nonisolated public init(destination: Destination, @ViewBuilder label: () -> Label) {
    nonisolated(unsafe) let destination = destination
    self.destination = destination
    self.label = label()
    activation = { $0.push(destination: AnyView(destination)) }
    activeRegistration = nil
    // Direct-destination links have no typed value to use as a route key, but
    // still receive a stable semantic href for browser adapters.
    navigationKey = _FiberKey("destination")
  }

 @_disfavoredOverload nonisolated public init<S: StringProtocol>(_ title: S, destination: Destination) where Label == Text {
    self.init(destination: destination) { Text(LocalizedStringKey(String(title)).resolved) }
  }
  nonisolated public init(_ titleKey: LocalizedStringKey, destination: Destination) where Label == Text { self.init(titleKey.resolved, destination: destination) }

 nonisolated public init<Value: Hashable>(value: Value, @ViewBuilder label: () -> Label) where Destination == EmptyView {
   nonisolated(unsafe) let value = value
    self.destination = EmptyView()
    self.label = label()
    activation = { $0.push(value) }
    activeRegistration = nil
    navigationKey = _FiberKey(value)
    selectionValue = _RuntimeValue(value)
  }

  /// `NavigationLink(value: selection.first)`: an absent value makes a link that does nothing. A separate overload,
  /// because Embedded Swift cannot build a `_FiberKey` from an arbitrary `Optional` generically.
  nonisolated public init<Value: Hashable>(value: Value?, @ViewBuilder label: () -> Label) where Destination == EmptyView {
    if let value {
      self = NavigationLink(value: value, label: label)
    } else {
      self.destination = EmptyView()
      self.label = label()
      activation = nil
      activeRegistration = nil
      navigationKey = nil
    }
  }

  /// `NavigationLink("Title") { Destination() }`.
  @_disfavoredOverload nonisolated public init<S: StringProtocol>(_ title: S, @ViewBuilder destination: () -> Destination) where Label == Text {
    self.init(destination: destination()) { Text(LocalizedStringKey(String(title)).resolved) }
  }
  nonisolated public init(_ titleKey: LocalizedStringKey, @ViewBuilder destination: () -> Destination) where Label == Text {
    self.init(titleKey.resolved, destination: destination)
  }

 @_disfavoredOverload nonisolated public init<Value: Hashable, S: StringProtocol>(_ title: S, value: Value) where Label == Text, Destination == EmptyView {
    self.init(value: value) { Text(LocalizedStringKey(String(title)).resolved) }
  }
  nonisolated public init<Value: Hashable>(_ titleKey: LocalizedStringKey, value: Value) where Label == Text, Destination == EmptyView { self.init(titleKey.resolved, value: value) }

 nonisolated public init(destination: Destination, isActive: Binding<Bool>, @ViewBuilder label: () -> Label) {
   nonisolated(unsafe) let destination = destination
    self.destination = destination
    self.label = label()
    activation = { _ in isActive.wrappedValue = true }
    activeRegistration = { context in
      context.registerActive(isPresented: { isActive.wrappedValue }, dismiss: { isActive.wrappedValue = false }, build: { AnyView(destination) })
    }
    navigationKey = nil
  }

 nonisolated public init<Value: Hashable>(destination: Destination, tag: Value, selection: Binding<Value?>, @ViewBuilder label: () -> Label) {
   nonisolated(unsafe) let destination = destination
   nonisolated(unsafe) let selection = selection
   nonisolated(unsafe) let tag = tag
    self.destination = destination
    self.label = label()
    activation = { _ in selection.wrappedValue = tag }
    activeRegistration = { context in
      context.registerActive(isPresented: { selection.wrappedValue == tag }, dismiss: { selection.wrappedValue = nil }, build: { AnyView(destination) })
    }
    navigationKey = _FiberKey(tag)
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("a")
    node.classes = ["navigation-link"]
    node.attributes["href"] = context.navigationContext?.href(for: navigationKey) ?? "#navigation"
    node.attributes["data-navigation-link"] = "push"
    if let selection = context.environment[_ListSelectionKey.self], let selectionValue {
      // Inside `List(selection:)` a value link selects its row, as in a sidebar; it does not push.
      node.events["click"] = _EventHandler(name: "click", action: { selection.select(selectionValue) }, preventsDefault: true)
      if selection.isSelected(selectionValue) {
        node.attributes["aria-current"] = "page"
        node.attributes["data-selected"] = "true"
        node.classes.append("item-selected")
      }
    } else if let navigationContext = context.navigationContext, let activation {
      node.events["click"] = _EventHandler(name: "click", action: { activation(navigationContext) }, preventsDefault: true)
    } else {
      node.events["click"] = _EventHandler(name: "click", action: {})
    }
    if let navigationContext = context.navigationContext { activeRegistration?(navigationContext) }
    // Under `.buttonStyle(.plain)` (or `.borderless`) a link is a plain button to SwiftUI: its label keeps the font and
    // the foreground style around it instead of the tint. Only those styles are marked: the layout reads an unmarked
    // link as plain too.
    let style = context.environment.buttonStyle.rawValue
    if !context.environment.buttonStyleIsCustom, style == "plain" || style == "borderless" {
      node.attributes["data-button-style"] = style
    }
    let child: _RenderNode
    if context.environment.buttonStyleIsCustom, !context.environment._buttonStyleIsPrimitive {
      // A link is a button to SwiftUI: an app-defined `ButtonStyle` draws its label, with a live `isPressed`.
      let click = node.events["click"]
      node.attributes["data-button-style-custom"] = "true"
      child = _renderButtonLabel(label, role: nil, action: { click?.action() }, node: node, context: context)
      _applyButtonVisibleShape(child, to: node)
    } else {
      child = label._render(in: context)
      // A plain link highlights and hit-tests the shape its label declares (`contentShape`), as a plain button does.
      if node.attributes["data-button-style"] == "plain" { _applyButtonVisibleShape(child, to: node) }
    }
    _markFlexibleWidthControl(child, control: node)
    if context.environment[_GroupedListKey.self], !child.isEmpty, context.environment[_ListSelectionKey.self] == nil {
      // A link in a form reads as a disclosure row: label, flexible space, chevron.
      let spacer = _RenderNode.element("div")
      spacer.classes = ["flex-spacer"]
      spacer.attributes["data-layout-kind"] = "spacer"
      spacer.attributes["data-layout-schema"] = "1"
      spacer.attributes["data-spacer-min"] = "12"
      let chevron = Image(systemName: "chevron.right")._render(in: context.child(_FiberKey("disclosure")))
      chevron.classes.append("disclosure-indicator")
      node.classes.append("hstack")
      node.attributes["data-layout-kind"] = "hstack"
      node.attributes["data-layout-schema"] = "1"
      node.attributes["data-layout-gap"] = _semanticNumber(0)
      node.attributes["data-align-x"] = "0.5"
      node.attributes["data-align-y"] = "0.5"
      node.children = [child, spacer, chevron]
      return node
    }
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

public struct ToolbarItemPlacement: Hashable, Sendable {
  let rawValue: String
  package init(_ rawValue: String) { self.rawValue = rawValue }
  public static let automatic = Self("automatic")
  public static let navigationBarLeading = Self("navigation-bar-leading")
  public static let navigationBarTrailing = Self("navigation-bar-trailing")
  // iOS 16's SwiftUI spelling; keep the same semantic placement token on
  // web so source can be moved between NavigationStack implementations.
  public static let topBarLeading = Self("top-bar-leading")
  public static let topBarTrailing = Self("top-bar-trailing")
  public static let principal = Self("principal")
  public static let confirmationAction = Self("confirmation-action")
  public static let cancellationAction = Self("cancellation-action")
  public static let primaryAction = Self("primary-action")
  public static let destructiveAction = Self("destructive-action")
  /// A bar at the foot of the navigation container; `NavigationStack` places these items below its content.
  public static let bottomBar = Self("bottom-bar")
}

/// The content of a toolbar item. A navigation bar shows a `Label` there as its icon alone (the title stays its
/// accessible name), so the default label style inside a bar is icon-only; a label style the content sets still wins.
@MainActor private func _toolbarItemContent<Content: View>(_ content: Content, in context: _RenderContext) -> _RenderNode {
  var barContext = context
  if barContext.environment._labelStyle == nil {
    barContext.environment._labelStyle = _LabelStyleRenderer(kind: .iconOnly, render: nil)
    barContext.environment._markLocalEnvironmentOverride()
  }
  return content._render(in: barContext)
}

public nonisolated struct ToolbarItem<Content: View>: View {
  public typealias Body = Never
  let placement: ToolbarItemPlacement
  let content: Content
  public nonisolated init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
    self.placement = placement
    self.content = content()
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["toolbar-item"]
    node.attributes["data-toolbar-placement"] = placement.rawValue
    let child = _toolbarItemContent(content, in: context)
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

public nonisolated struct ToolbarItemGroup<Content: View>: View {
  public typealias Body = Never
  let placement: ToolbarItemPlacement
  let content: Content
  public nonisolated init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
    self.placement = placement
    self.content = content()
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["toolbar-group"]
    node.attributes["data-toolbar-group-placement"] = placement.rawValue
    let child = _toolbarItemContent(content, in: context)
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

nonisolated struct NavigationDestinationModifier<Value: Hashable, Destination: View>: ViewModifier {
  let value: Value.Type
  let destination: (Value) -> Destination
  public init(value: Value.Type, destination: @escaping (Value) -> Destination) {
    self.value = value
    self.destination = destination
  }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    if let navigation = context.navigationContext {
      _renderRegistersWithAncestors()
      navigation.registry.register(value: value, destination: destination)
    } else {
      let setup = context.navigationSetup ?? _NavigationSetup()
      context.navigationSetup = setup
      _renderRegistersWithAncestors()
      setup.registry.register(value: value, destination: destination)
    }
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-navigation-destination"] = "registered"
  }
}

nonisolated struct PresentedNavigationDestinationModifier<Destination: View>: ViewModifier {
  let isPresented: Binding<Bool>
  let destination: () -> Destination
  public init(isPresented: Binding<Bool>, destination: @escaping () -> Destination) {
    self.isPresented = isPresented
    self.destination = destination
  }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    if let navigation = context.navigationContext {
      navigation.registerActive(
        isPresented: { isPresented.wrappedValue },
        dismiss: { isPresented.wrappedValue = false },
        build: { AnyView(destination()) }
      )
    } else {
      let setup = context.navigationSetup ?? _NavigationSetup()
      context.navigationSetup = setup
      _renderRegistersWithAncestors()
      setup.registry.active.append(_ActiveNavigationDestination(
        isPresented: { isPresented.wrappedValue },
        dismiss: { isPresented.wrappedValue = false },
        build: { AnyView(destination()) }
      ))
    }
  }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
nonisolated struct ItemNavigationDestinationModifier<Item: Identifiable, Destination: View>: ViewModifier {
  let item: Binding<Item?>
  let destination: (Item) -> Destination
  public init(item: Binding<Item?>, destination: @escaping (Item) -> Destination) {
    self.item = item
    self.destination = destination
  }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    let active = _ActiveNavigationDestination(
      isPresented: { item.wrappedValue != nil },
      dismiss: { item.wrappedValue = nil },
      build: {
        guard let value = item.wrappedValue else { return AnyView(EmptyView()) }
        return AnyView(destination(value))
      }
    )
    if let navigation = context.navigationContext {
      _renderRegistersWithAncestors()
      navigation.registry.active.append(active)
    } else {
      let setup = context.navigationSetup ?? _NavigationSetup()
      context.navigationSetup = setup
      _renderRegistersWithAncestors()
      setup.registry.active.append(active)
    }
  }
}

nonisolated struct NavigationTitleModifier: ViewModifier {
  let title: String
  public init(title: String) { self.title = title }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    if let navigation = context.navigationContext {
      _renderRegistersWithAncestors()
      navigation.title = title
    } else {
      let setup = context.navigationSetup ?? _NavigationSetup()
      context.navigationSetup = setup
      _renderRegistersWithAncestors()
      setup.title = title
    }
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-navigation-title"] = title
  }
}

nonisolated struct NavigationBarTitleDisplayModeModifier: ViewModifier {
  let mode: NavigationBarItem.TitleDisplayMode
  init(mode: NavigationBarItem.TitleDisplayMode) { self.mode = mode }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    if let navigation = context.navigationContext {
      _renderRegistersWithAncestors()
      navigation.titleDisplayMode = mode
    } else {
      let setup = context.navigationSetup ?? _NavigationSetup()
      context.navigationSetup = setup
      _renderRegistersWithAncestors()
      setup.titleDisplayMode = mode
    }
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-navigation-title-display-mode"] = mode._attributeValue
  }
}

public extension View {
  nonisolated func navigationDestination<Value: Hashable, Destination: View>(
    for value: Value.Type,
    @ViewBuilder destination: @escaping (Value) -> Destination
  ) -> some View {
    modifier(NavigationDestinationModifier(value: value, destination: destination))
  }

  nonisolated func navigationDestination<Destination: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder destination: @escaping () -> Destination
  ) -> some View {
    modifier(PresentedNavigationDestinationModifier(isPresented: isPresented, destination: destination))
  }

  nonisolated func navigationDestination<Item: Hashable, Destination: View>(
    item: Binding<Optional<Item>>,
    @ViewBuilder destination: @escaping (Item) -> Destination
  ) -> some View {
    // The stack identifies each item by its Hashable value; the wrapper supplies the Identifiable the modifier stores.
    let wrapped = Binding<_HashableIdentified<Item>?>(
      _unchecked: { item.wrappedValue.map { _HashableIdentified($0) } },
      set: { item.wrappedValue = $0?.value })
    return modifier(ItemNavigationDestinationModifier(item: wrapped, destination: { destination($0.value) }))
  }

  nonisolated func navigationTitle<S: StringProtocol>(_ title: S) -> some View {
    // A string literal reaches this overload before the LocalizedStringKey one, so a registered key is translated
    // here; any other string resolves to itself.
    modifier(NavigationTitleModifier(title: LocalizedStringKey(String(title)).resolved))
  }

  nonisolated func navigationTitle(_ title: Text) -> some View {
    modifier(NavigationTitleModifier(title: title.value))
  }

  nonisolated func navigationTitle(_ titleKey: LocalizedStringKey) -> some View {
    modifier(NavigationTitleModifier(title: titleKey.resolved))
  }

  nonisolated func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View {
    modifier(NavigationBarTitleDisplayModeModifier(mode: mode))
  }
}

#if !hasFeature(Embedded)
extension TabViewCustomization: Codable {}
#endif

/// Bridges a typed collection binding to the stack's `NavigationPath`. The
/// history observer lives with the NavigationPath value; a typed collection
/// cannot hold it, so the bridge keeps it beside the binding.
private final class _TypedNavigationPathBridge {
  var observer: _NavigationPathObserver?
}

private func _typedNavigationPathBinding<Data>(_ path: Binding<Data>) -> Binding<NavigationPath>
where Data: MutableCollection & RandomAccessCollection & RangeReplaceableCollection,
      Data.Element: Hashable {
  let bridge = _TypedNavigationPathBridge()
  return Binding(
    _unchecked: {
      var result = NavigationPath(path.wrappedValue)
      result._observer = bridge.observer
      return result
    },
    set: { next in
      bridge.observer = next._observer
      guard let values = next._typedElements(Data.Element.self) else { return }
      let current = path.wrappedValue
      if current.count == values.count && zip(current, values).allSatisfy({ $0 == $1 }) { return }
      path.wrappedValue = Data(values)
    }
  )
}
