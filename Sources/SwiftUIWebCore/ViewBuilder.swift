@_spi(Renderer) import SwiftUIWebTransferable
@resultBuilder public enum ViewBuilder {
  // Empty blocks do not participate in buildPartialBlock's first/next chain.
  public static func buildBlock() -> EmptyView { EmptyView() }

  // Retain the historical direct helper for callers that use buildBlock
  // explicitly. Result-builder closures use the partial-block methods below.
  public static func buildBlock<C: View>(_ content: C) -> C { content }

  public static func buildPartialBlock<Content: View>(first content: Content) -> Content {
    content
  }

  public static func buildPartialBlock<First: View, Next: View>(
    accumulated: First,
    next: Next
  ) -> _ViewBuilderContent<Never> {
    _ViewBuilderContent(
      childAppenders: [
        _viewBuilderChildAppender(accumulated),
        _viewBuilderChildAppender(next)
      ]
    )
  }

  public static func buildPartialBlock<Next: View>(
    accumulated: _ViewBuilderContent<Never>,
    next: Next
  ) -> _ViewBuilderContent<Never> {
    var childAppenders = accumulated.childAppenders
    childAppenders.append(_viewBuilderChildAppender(next))
    return _ViewBuilderContent(childAppenders: childAppenders)
  }

  public static func buildEither<TrueContent: View, FalseContent: View>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent> { .trueContent(first) }
  public static func buildEither<TrueContent: View, FalseContent: View>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent> { .falseContent(second) }
  public static func buildIf<Content: View>(_ component: Content?) -> _ConditionalContent<Content, EmptyView> { component.map(_ConditionalContent.trueContent) ?? .falseContent(EmptyView()) }
 public static func buildLimitedAvailability<Content: View>(_ component: Content) -> AnyView { AnyView(component) }
}

/// Modern SwiftUI spelling for closures that produce view content.
///
/// `ContentBuilder` aliases `ViewBuilder` to preserve the existing
/// SwiftUIWeb view-building behavior and source compatibility for
/// `@ViewBuilder` clients.
public typealias ContentBuilder = ViewBuilder

public struct Group {
  public typealias Body = Never
  package let content: [AnyView]
 nonisolated public init<Content: View>(@ViewBuilder content: () -> Content) { self.content = [AnyView(content())] }
  init(_ content: [AnyView]) { self.content = content }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let fragment = _RenderNode.fragment()
    fragment.children = content.enumerated().map { index, child in
      child._render(in: context.child(_FiberKey(index)))
    }
    return fragment
  }
}
extension Group: View {}

public nonisolated struct TupleView<T>: View {
  public typealias Body = Never
  fileprivate let content: [AnyView]
  /// The renderer's storage form: the children, already type-erased.
  package init(_ content: [AnyView]) { self.content = content }

  // SwiftUI's `init(_ value: T)` for a tuple of views. The generic initializer
  // over a parameter pack is rejected by Embedded Swift, so each arity has its own.
  public init<A: View, B: View>(_ value: (A, B)) where T == (A, B) {
    self.content = [AnyView(value.0), AnyView(value.1)]
  }

  public init<A: View, B: View, C: View>(_ value: (A, B, C)) where T == (A, B, C) {
    self.content = [AnyView(value.0), AnyView(value.1), AnyView(value.2)]
  }

  public init<A: View, B: View, C: View, D: View>(_ value: (A, B, C, D)) where T == (A, B, C, D) {
    self.content = [AnyView(value.0), AnyView(value.1), AnyView(value.2), AnyView(value.3)]
  }

  public init<A: View, B: View, C: View, D: View, E: View>(_ value: (A, B, C, D, E)) where T == (A, B, C, D, E) {
    self.content = [AnyView(value.0), AnyView(value.1), AnyView(value.2), AnyView(value.3), AnyView(value.4)]
  }

  public init<A: View, B: View, C: View, D: View, E: View, F: View>(_ value: (A, B, C, D, E, F)) where T == (A, B, C, D, E, F) {
    self.content = [AnyView(value.0), AnyView(value.1), AnyView(value.2), AnyView(value.3), AnyView(value.4), AnyView(value.5)]
  }

  public init<A: View, B: View, C: View, D: View, E: View, F: View, G: View>(_ value: (A, B, C, D, E, F, G)) where T == (A, B, C, D, E, F, G) {
    self.content = [AnyView(value.0), AnyView(value.1), AnyView(value.2), AnyView(value.3), AnyView(value.4), AnyView(value.5), AnyView(value.6)]
  }

  public init<A: View, B: View, C: View, D: View, E: View, F: View, G: View, H: View>(_ value: (A, B, C, D, E, F, G, H)) where T == (A, B, C, D, E, F, G, H) {
    self.content = [AnyView(value.0), AnyView(value.1), AnyView(value.2), AnyView(value.3), AnyView(value.4), AnyView(value.5), AnyView(value.6), AnyView(value.7)]
  }

  public init<A: View, B: View, C: View, D: View, E: View, F: View, G: View, H: View, I: View>(_ value: (A, B, C, D, E, F, G, H, I)) where T == (A, B, C, D, E, F, G, H, I) {
    self.content = [AnyView(value.0), AnyView(value.1), AnyView(value.2), AnyView(value.3), AnyView(value.4), AnyView(value.5), AnyView(value.6), AnyView(value.7), AnyView(value.8)]
  }

  public init<A: View, B: View, C: View, D: View, E: View, F: View, G: View, H: View, I: View, J: View>(_ value: (A, B, C, D, E, F, G, H, I, J)) where T == (A, B, C, D, E, F, G, H, I, J) {
    self.content = [AnyView(value.0), AnyView(value.1), AnyView(value.2), AnyView(value.3), AnyView(value.4), AnyView(value.5), AnyView(value.6), AnyView(value.7), AnyView(value.8), AnyView(value.9)]
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    Group(content)._render(in: context)
  }
}

/// Heap storage for a view held by a wrapper type. Wrapper types nest by
/// type (`ModifiedContent<ModifiedContent<…>>`, `_ConditionalContent<
/// _ConditionalContent<…>>`); holding the wrapped view by value made every
/// level's copy, destroy and closure-context witnesses copy the whole chain
/// beneath it. Through a box each level copies one pointer.
public final class _ViewBox<Value> {
  public let value: Value
  public init(_ value: Value) { self.value = value }
}

/// One branch of an `if`/`else` or `if let` in a view builder. The branch
/// value is boxed (see `_ViewBox`); `trueContent`/`falseContent` keep the
/// enum-case spelling the builders and the lowerer use.
/// The branch types are unconstrained, as in SwiftUI: table builders return
/// `_ConditionalContent` for their table content, and the `View` conformance
/// applies only when both branches are views.
public struct _ConditionalContent<TrueContent, FalseContent> {
  package enum Branch {
    case trueContent(_ViewBox<TrueContent>)
    case falseContent(_ViewBox<FalseContent>)
  }
  let branch: Branch
  public static func trueContent(_ value: TrueContent) -> Self { Self(branch: .trueContent(_ViewBox(value))) }
  public static func falseContent(_ value: FalseContent) -> Self { Self(branch: .falseContent(_ViewBox(value))) }
}

extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
  public typealias Body = Never

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // Only the erasure depends on the branch types; keying, the branch
    // context and the state-scope path are rendered once in `_renderBranch`.
    switch branch {
    case .trueContent(let box): return _renderBranch(AnyView(box.value), taken: true, in: context)
    case .falseContent(let box): return _renderBranch(AnyView(box.value), taken: false, in: context)
    }
  }
}

extension _ConditionalContent: TableColumnContent
where TrueContent: TableColumnContent, FalseContent: TableColumnContent,
  TrueContent.TableRowValue == FalseContent.TableRowValue,
  TrueContent.TableColumnSortComparator == FalseContent.TableColumnSortComparator {
  public typealias TableRowValue = TrueContent.TableRowValue
  public typealias TableColumnSortComparator = TrueContent.TableColumnSortComparator
  public typealias TableColumnBody = Never

  public func _renderTableColumns(in context: _RenderContext) -> _RenderNode {
    switch branch {
    case .trueContent(let box): return box.value._renderTableColumns(in: context.child(_FiberKey("true")))
    case .falseContent(let box): return box.value._renderTableColumns(in: context.child(_FiberKey("false")))
    }
  }
}

extension _ConditionalContent: TableRowContent
where TrueContent: TableRowContent, FalseContent: TableRowContent, TrueContent.TableRowValue == FalseContent.TableRowValue {
  public typealias TableRowValue = TrueContent.TableRowValue
  public typealias TableRowBody = Never

  public func _renderTableRows(in context: _RenderContext) -> _RenderNode {
    switch branch {
    case .trueContent(let box): return box.value._renderTableRows(in: context.child(_FiberKey("true")))
    case .falseContent(let box): return box.value._renderTableRows(in: context.child(_FiberKey("false")))
    }
  }
}

/// Renders the branch of a conditional that was taken. `_renderBranch` sits on the render recursion, so the work
/// around the nested render (the branch's context and key before it, its state-scope path after it) lives in
/// separate functions that are off the stack while the branch renders.
@inline(never)
@MainActor func _renderBranch(_ view: AnyView, taken: Bool, in context: _RenderContext) -> _RenderNode {
  let branchContext = _branchContext(context, taken: taken)
  let node = _keyedBranch(view, taken: taken, slot: context._fiberPath.last)._render(in: branchContext)
  _recordBranchScope(node, in: branchContext)
  return node
}

@inline(never)
@MainActor private func _branchContext(_ context: _RenderContext, taken: Bool) -> _RenderContext {
  context.child(_FiberKey(taken ? "true" : "false"))
}

/// A branch sits among its parent's children under its key, not its position, so the key names the slot the conditional
/// fills (`slot`, the last key of its context: its place in the view builder) as well as the branch. Two `if`s of one
/// builder are then two identities, as in SwiftUI. With the branch alone, the second of two taken `if`s was a duplicate of
/// the first, and became another view whenever the first one appeared or went away: new fibers, event routes, state and
/// focus.
@inline(never)
@MainActor private func _keyedBranch(_ view: AnyView, taken: Bool, slot: _FiberKey?) -> AnyView {
  let branch = taken ? "__if" : "__else"
  return view._withKey(_FiberKey(slot.map { branch + "@" + fiberKeyDescription($0) } ?? branch))
}

@inline(never)
@MainActor private func _recordBranchScope(_ node: _RenderNode, in branchContext: _RenderContext) {
  if node._isPendingRender {
    node._keep(.stateScopePath(branchContext._fiberPath))
  } else {
    _recordStateScopePath(node, path: branchContext._fiberPath)
  }
}

/// A binding to the element that was at `index` when the rows were built. The collection may change before the row
/// renders or after, so the element is found again by its id: at `index` while it is still there, elsewhere when the
/// collection moved it. A read with no such element returns the last value seen; a write with none does nothing.
private func _identifiedElementBinding<C: RandomAccessCollection & MutableCollection>(
  _ data: Binding<C>,
  at index: C.Index,
  initial: C.Element
) -> Binding<C.Element> where C.Element: Identifiable {
  let id = initial.id
  var lastSeen = initial
  func position(in collection: C) -> C.Index? {
    if index < collection.endIndex, collection[index].id == id { return index }
    return collection.indices.first(where: { collection[$0].id == id })
  }
  return Binding(_unchecked: {
    let current = data.wrappedValue
    if let found = position(in: current) { lastSeen = current[found] }
    return lastSeen
  }, set: { newValue in
    guard let found = position(in: data.wrappedValue) else { return }
    data.wrappedValue[found] = newValue
  })
}

extension ForEach {
  /// `ForEach($items) { $item in ... }`: one binding per element of an identifiable, mutable collection.
 @_disfavoredOverload public init<C: RandomAccessCollection & MutableCollection>(_ data: Binding<C>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content)
    where C.Element: Identifiable, C.Element.ID == ID, Data == [Binding<C.Element>], Content: View {
    var bindings: [Binding<C.Element>] = []
    let snapshot = data.wrappedValue
    var position = snapshot.startIndex
    while position < snapshot.endIndex {
      bindings.append(_identifiedElementBinding(data, at: position, initial: snapshot[position]))
      position = snapshot.index(after: position)
    }
    self.data = bindings
    self.keyProvider = { _FiberKey($0.wrappedValue.id) }
    self.content = content
  }
}

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content> {
  public let data: Data
  // Keep identity extraction as a closure so Embedded builds can use the
  // hashable element overload without constructing a runtime KeyPath. The
  // key-path initializer remains source-compatible for regular Swift apps.
  private let keyProvider: (Data.Element) -> _FiberKey
  public let content: (Data.Element) -> Content

  // The View initializers below are constrained to `Content: View`, as SwiftUI's are. Without the constraint a
  // `TabView` closure's `ForEach(_:id:) { Tab(...) }` also matches this `@ViewBuilder` spelling, which is then
  // chosen over the `TabContent` overload and fails with `buildPartialBlock(first:)` requires View.
  public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) where Content: View {
    self.data = data
    self.keyProvider = { _FiberKey($0[keyPath: id]) }
    self.content = content
  }

  /// Embedded lowering target for SwiftUI's `ForEach(data, id: \.member)` spelling.
  /// User source keeps the key-path API; the browser build rewrites only the
  /// compiler input to this closure form before Embedded Swift sees it. It is
  /// SPI so the public surface stays SwiftUI's key-path initializer.
  /// Unconstrained forms for other modules' content builders (Charts) that forward a non-`View` content closure.
  package init(_forwarding data: Data, id: KeyPath<Data.Element, ID>, content: @escaping (Data.Element) -> Content) {
    self.data = data
    self.keyProvider = { _FiberKey($0[keyPath: id]) }
    self.content = content
  }

  package init(_forwarding data: Data, id: @escaping (Data.Element) -> ID, content: @escaping (Data.Element) -> Content) {
    self.data = data
    self.keyProvider = { _FiberKey(id($0)) }
    self.content = content
  }

  @_spi(Renderer) public init(_ data: Data, id: @escaping (Data.Element) -> ID, @ViewBuilder content: @escaping (Data.Element) -> Content) where Content: View {
    self.data = data
    self.keyProvider = { _FiberKey(id($0)) }
    self.content = content
  }

  /// SwiftUI-style convenience for collections whose elements are themselves
  /// stable hashable identities. This overload is also the Embedded-friendly
  /// path because it does not require key-path literals or reflection.
  /// SwiftUI identifies `Identifiable` elements by `id`, so this overload is
  /// disfavored: an element that is both `Hashable` and `Identifiable` uses
  /// the `Identifiable` initializer, exactly as in SwiftUI.
  @_disfavoredOverload
  public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content)
    where Data.Element: Hashable, ID == Data.Element, Content: View {
    self.data = data
    self.keyProvider = { _FiberKey($0) }
    self.content = content
  }

}

extension ForEach: View where Content: View {
  public typealias Body = Never

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // Only the element lookup and the `content` call depend on this
    // ForEach's type parameters; everything else is rendered by the shared
    // non-generic `_renderKeyedCollection`, so an application pays one small
    // specialization per ForEach type rather than the whole algorithm.
    let data = self.data
    let content = self.content
    #if hasFeature(Embedded)
    let itemType = ""
    #else
    let itemType = _swiftUIWebTypeName(Content.self)
    #endif
    return _renderKeyedCollection(in: context, keys: data.map(keyProvider), itemType: itemType) { offset in
      let element = data[data.index(data.startIndex, offsetBy: offset)]
      return AnyView { content(element) }
    }
  }
}

/// `ForEach` rows of a `Table`: each element supplies one row of its content.
extension ForEach: TableRowContent where Content: TableRowContent {
  public typealias TableRowValue = Content.TableRowValue
  public typealias TableRowBody = Never

  public func _renderTableRows(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.fragment()
    let keys = _occurrenceKeys(data.map(keyProvider))
    var offset = 0
    node.children = data.map { element in
      let key = keys[offset]
      offset += 1
      return content(element)._renderTableRows(in: context.child(key))
    }
    return node
  }
}

/// `ForEach` tabs of a `TabView`: each element supplies its tab content in order.
extension ForEach: TabContent where Content: TabContent {
  public typealias TabValue = Content.TabValue
  public typealias Body = Never

  @_spi(Renderer) @MainActor public func _renderTabContent(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.fragment()
    let keys = _occurrenceKeys(data.map(keyProvider))
    var offset = 0
    node.children = data.map { element in
      let key = keys[offset]
      offset += 1
      // Each element is an owner boundary, as an erased view is for ViewBuilder
      // content: a model read while building its tab (a title) re-renders that tab alone.
      let tab = AnyView(_ownerBoundary: { context in
        // The element's view is built and rendered under its own scope, first render and retained render alike,
        // so its `@State` and `@Environment` resolve the same way in both.
        let saved = _enterRenderScope(context, viewTag: "tab")
        defer { _exitRenderScope(saved) }
        return content(element)._renderTabContent(in: context)
      })
      return tab._render(in: context.child(key))
    }
    return node
  }
}

extension ForEach where Content: TabContent {
  @_disfavoredOverload
  nonisolated public init<V>(_ data: Data, id: KeyPath<Data.Element, ID>, @TabContentBuilder<V> content: @escaping (Data.Element) -> Content) where V == Content.TabValue {
    self.data = data
    self.keyProvider = { _FiberKey($0[keyPath: id]) }
    self.content = content
  }
}

/// The closure-identity spelling the Embedded lowerer rewrites `ForEach(data, id: \.member)` into (see the View
/// initializer above). Tabs need it too, or the lowered `ForEach` of tabs matches only the View initializer.
extension ForEach where Content: TabContent {
  @_spi(Renderer) nonisolated public init<V>(_ data: Data, id: @escaping (Data.Element) -> ID, @TabContentBuilder<V> content: @escaping (Data.Element) -> Content) where V == Content.TabValue {
    self.data = data
    self.keyProvider = { _FiberKey(id($0)) }
    self.content = content
  }
}

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID, Content: TabContent {
  public init<V>(_ data: Data, @TabContentBuilder<V> content: @escaping (Data.Element) -> Content) where V == Content.TabValue {
    self.data = data
    self.keyProvider = { _FiberKey($0.id) }
    self.content = content
  }
}

extension ForEach where Data.Element: Hashable, ID == Data.Element, Content: TabContent {
  @_disfavoredOverload
  public init<V>(_ data: Data, @TabContentBuilder<V> content: @escaping (Data.Element) -> Content) where V == Content.TabValue {
    self.data = data
    self.keyProvider = { _FiberKey($0) }
    self.content = content
  }
}

/// The fiber keys of a collection's elements: a later element with the same identity gets its own occurrence, so two
/// rows or tabs with one id never share a fiber path (and their state).
func _occurrenceKeys(_ semanticKeys: [_FiberKey]) -> [_FiberKey] {
  var occurrences: [_FiberKey: Int] = .init()
  return semanticKeys.map { key in
    let occurrence = occurrences[key, default: 0]
    occurrences[key] = occurrence + 1
    return _fiberKeyWithOccurrence(key, occurrence)
  }
}

/// A lazy collection's keys by offset, for its `containsKey`. A table rather than a `Set`: Embedded Swift emits the
/// hashed-collection code once per element type, and `_occurrenceKeys` already has the one for `[_FiberKey: Int]`.
func _lazyKeyOffsets(_ keys: [_FiberKey]) -> [_FiberKey: Int] {
  var offsets: [_FiberKey: Int] = .init()
  for (offset, key) in keys.enumerated() { offsets[key] = offset }
  return offsets
}

/// The type-independent part of a `ForEach` render: occurrence-suffixed keys,
/// the deferred descriptor under a lazy container or the eager fragment, and
/// the keyed row contexts. `item` returns the erased row for a logical offset.
///
/// A ForEach below a lazy container is represented as a deferred collection
/// descriptor. Browser hosts materialize the visible logical range through
/// Fiber; static/WASI hosts never set `lazyAxis` and retain the historical
/// eager tree for deterministic HTML output. Explicit Lazy* containers force
/// deferral even for short collections, while List/Table retain the
/// small-collection eager fast path.
@inline(never)
@MainActor func _renderKeyedCollection(
  in context: _RenderContext,
  keys semanticKeys: [_FiberKey],
  itemType: String,
  item: @escaping (Int) -> AnyView
) -> _RenderNode {
  let keys = _occurrenceKeys(semanticKeys)
  let count = keys.count
  if context.lazyCollectionsEnabled, let axis = context.lazyAxis,
     context.lazyCollectionsForceDeferred || count > _lazyCollectionThreshold {
    let keyOffsets = _lazyKeyOffsets(keys)
    let environment = context.environment
    // Rows materialized later by the host start from a fresh context, so the enclosing
    // NavigationStack's runtime context must be carried over too: without it a
    // NavigationLink in a lazy row renders href="#navigation" and does nothing.
    let navigationContext = context.navigationContext
    let descriptor = _LazyCollectionDescriptor(
      count: count,
      axis: axis,
      estimatedExtent: axis == .vertical ? 64 / Double(max(1, context.lazyLaneCount ?? 1)) : 160,
      laneCount: context.lazyLaneCount ?? 1,
      itemType: itemType,
      keyAt: { offset in keys[offset] },
      containsKey: { keyOffsets[$0] != nil },
      renderItem: { offset, itemContext in
        let key = keys[offset]
        // Rows materialized later by the host must see the environment in
        // effect where this ForEach was declared (including objects from
        // `.environment(_:)`), exactly as eagerly rendered rows do.
        var rowContext = itemContext
        rowContext.environment = environment
        if rowContext.navigationContext == nil { rowContext.navigationContext = navigationContext }
        return item(offset)._withKey(key, overriding: true)._render(in: rowContext.child(key))
      }
    )
    let placeholder = _RenderNode.fragment()
    placeholder.lazyCollection = descriptor
    return placeholder
  }
  let fragment = _RenderNode.fragment()
  fragment.children = (0..<count).map { offset in
    let key = keys[offset]
    return item(offset)._withKey(key, overriding: true)._render(in: context.child(key))
  }
  return fragment
}

@available(macOS 10.15, iOS 13.0, *)
extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
  public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
    self.data = data
    self.keyProvider = { _FiberKey($0.id) }
    self.content = content
  }
}

/// `ForEach(rows) { TableRow($0) }` inside a `Table`'s `rows:` closure. Table
/// rows are not views, so this initializer takes a single-expression closure
/// rather than a view builder.
extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID, Content: TableRowContent {
  public init(_ data: Data, content: @escaping (Data.Element) -> Content) {
    self.data = data
    self.keyProvider = { _FiberKey($0.id) }
    self.content = content
  }
}
