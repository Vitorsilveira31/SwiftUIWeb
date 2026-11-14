// The `TabContent` protocol and `TabContentBuilder`: the tab declarations a
// `TabView` accepts (`Tab`, `TabSection`, `ForEach` of tabs, `if`/`else`).
// Apple's `TabContent`, `TabContentBuilder`, `AnyTabContent` and the builder's
// fixed-arity `buildBlock` overloads; the arity overloads (not a variadic
// `buildPartialBlock`) carry multi-child blocks, because Embedded Swift cannot
// specialize packs.
//
// Rendering goes through `_renderTabContent`: primitives render their node
// (a `Tab` renders its tagged panel, a `TabSection` a section marker) and
// composites forward to their children, so `TabView` can walk the result for
// its tab list. Primitive tab content has `Body == Never`, like views.

@MainActor @preconcurrency public protocol TabContent<TabValue> {
  associatedtype TabValue: Hashable
  // Unconstrained so that `Never` (the body of primitive tab content) needs no
  // conformance of its own; composite content constrains `Body` in the default below.
  associatedtype Body
  @TabContentBuilder<TabValue> @MainActor @preconcurrency var body: Body { get }

  /// SwiftUIWeb's renderer hook. `TabView` collects the tagged nodes it returns.
  @_spi(Renderer) @MainActor func _renderTabContent(in context: _RenderContext) -> _RenderNode
}

public extension TabContent where Body == Never {
  var body: Never { fatalError("Primitive tab content does not expose a body") }
}

public extension TabContent where Body: TabContent {
  @_spi(Renderer) @MainActor func _renderTabContent(in context: _RenderContext) -> _RenderNode {
    body._renderTabContent(in: context)
  }
}

/// Tab content carrying a view modifier's metadata. The modifier writes to the
/// tab's own node, where `TabView` reads badges and customization identifiers,
/// so tab modifiers share their implementation with the `View` modifiers.
nonisolated package struct _TabModifiedContent<Content: TabContent, Modifier: ViewModifier>: TabContent {
  package typealias TabValue = Content.TabValue
  package typealias Body = Never
  let content: Content
  let modifier: Modifier

  package init(content: Content, modifier: Modifier) {
    self.content = content
    self.modifier = modifier
  }

  @MainActor package func _renderTabContent(in context: _RenderContext) -> _RenderNode {
    var modifiedContext = context
    modifier._modifyContext(&modifiedContext)
    let node = content._renderTabContent(in: modifiedContext)
    modifier._apply(to: node, context: &modifiedContext)
    return node
  }
}

public extension TabContent {
  nonisolated func badge(_ count: Int) -> some TabContent<TabValue> {
    _TabModifiedContent(content: self, modifier: _badgeModifier(count))
  }

  /// SwiftUI's label badge: `nil` removes the badge.
  nonisolated func badge(_ label: Text?) -> some TabContent<TabValue> {
    _TabModifiedContent(content: self, modifier: _badgeModifier(label))
  }

  nonisolated func badge(_ key: LocalizedStringKey?) -> some TabContent<TabValue> {
    _TabModifiedContent(content: self, modifier: _badgeModifier(key.map { $0.resolved }))
  }

  @_disfavoredOverload nonisolated func badge<S: StringProtocol>(_ label: S?) -> some TabContent<TabValue> {
    _TabModifiedContent(content: self, modifier: _badgeModifier(label.map { String($0) }))
  }

  nonisolated func disabled(_ disabled: Bool) -> some TabContent<TabValue> {
    _TabModifiedContent(content: self, modifier: _disabledModifier(disabled))
  }

}

/// Groups the rendered children of a tab builder block into one fragment.
@MainActor func _tabFragment(_ parts: [_RenderNode]) -> _RenderNode {
  let node = _RenderNode.fragment()
  node.children = parts
  return node
}

/// The result of a `TabContentBuilder` block with several children. Apple's
/// `_TupleTabContent`; the children are kept in their tuple and rendered in order.
nonisolated struct _TupleTabContent<Value, T>: TabContent where Value: Hashable {
  typealias TabValue = Value
  typealias Body = Never
  let value: T
  let renderer: @MainActor (T, _RenderContext) -> _RenderNode

  nonisolated init(value: T, renderer: @escaping @MainActor (T, _RenderContext) -> _RenderNode) {
    self.value = value
    self.renderer = renderer
  }

  @MainActor func _renderTabContent(in context: _RenderContext) -> _RenderNode { renderer(value, context) }
}

/// Type-erased tab content, produced by `if #available` branches. Apple's `AnyTabContent`.
public nonisolated struct AnyTabContent<TabValue>: TabContent where TabValue: Hashable {
  public typealias Body = Never
  private let renderer: @MainActor (_RenderContext) -> _RenderNode

  public nonisolated init<C: TabContent>(_ content: C) where C.TabValue == TabValue {
    // SAFETY: the main-actor closure below is the only user of `content`, and it runs on the main actor.
    nonisolated(unsafe) let content = content
    renderer = { context in content._renderTabContent(in: context) }
  }

  @_spi(Renderer) @MainActor public func _renderTabContent(in context: _RenderContext) -> _RenderNode {
    renderer(context)
  }
}

/// The result builder for `TabView` content, `TabSection` content and `ForEach` of tabs. Apple's `TabContentBuilder`.
@resultBuilder public struct TabContentBuilder<TabValue> where TabValue: Hashable {
  /// A `TabContentBuilder` block wrapped as a view, the content type `TabView` stores. Apple's `TabContentBuilder.Content`.
  public nonisolated struct Content<C>: View where C: TabContent {
    public typealias Body = Never
    let tabContent: C

    init(_ tabContent: C) { self.tabContent = tabContent }

    @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
      tabContent._renderTabContent(in: context)
    }
  }

  public static func buildExpression(_ content: some TabContent<TabValue>) -> some TabContent<TabValue> {
    content
  }

  public static func buildBlock(_ content: some TabContent<TabValue>) -> some TabContent<TabValue> {
    content
  }

  public static func buildIf(_ content: (some TabContent<TabValue>)?) -> (some TabContent<TabValue>)? {
    content
  }

  public static func buildEither<T, F>(first: T) -> _ConditionalContent<T, F>
  where TabValue == T.TabValue, T: TabContent, F: TabContent, T.TabValue == F.TabValue {
    .trueContent(first)
  }

  public static func buildEither<T, F>(second: F) -> _ConditionalContent<T, F>
  where TabValue == T.TabValue, T: TabContent, F: TabContent, T.TabValue == F.TabValue {
    .falseContent(second)
  }

  public static func buildLimitedAvailability<T>(_ content: T) -> AnyTabContent<T.TabValue> where T: TabContent {
    AnyTabContent(content)
  }

  public static func buildBlock<C0, C1>(_ c0: C0, _ c1: C1) -> some TabContent<TabValue>
  where TabValue == C0.TabValue,
        C0: TabContent,
        C1: TabContent,
        C1.TabValue == C0.TabValue {
    _TupleTabContent<TabValue, (C0, C1)>(value: (c0, c1), renderer: { value, context in
      _tabFragment([value.0._renderTabContent(in: context.child(_FiberKey("tab_0"))), value.1._renderTabContent(in: context.child(_FiberKey("tab_1")))])
    })
  }

  public static func buildBlock<C0, C1, C2>(_ c0: C0, _ c1: C1, _ c2: C2) -> some TabContent<TabValue>
  where TabValue == C0.TabValue,
        C0: TabContent,
        C1: TabContent,
        C2: TabContent,
        C1.TabValue == C0.TabValue,
        C2.TabValue == C0.TabValue {
    _TupleTabContent<TabValue, (C0, C1, C2)>(value: (c0, c1, c2), renderer: { value, context in
      _tabFragment([value.0._renderTabContent(in: context.child(_FiberKey("tab_0"))), value.1._renderTabContent(in: context.child(_FiberKey("tab_1"))), value.2._renderTabContent(in: context.child(_FiberKey("tab_2")))])
    })
  }

  public static func buildBlock<C0, C1, C2, C3>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> some TabContent<TabValue>
  where TabValue == C0.TabValue,
        C0: TabContent,
        C1: TabContent,
        C2: TabContent,
        C3: TabContent,
        C1.TabValue == C0.TabValue,
        C2.TabValue == C0.TabValue,
        C3.TabValue == C0.TabValue {
    _TupleTabContent<TabValue, (C0, C1, C2, C3)>(value: (c0, c1, c2, c3), renderer: { value, context in
      _tabFragment([value.0._renderTabContent(in: context.child(_FiberKey("tab_0"))), value.1._renderTabContent(in: context.child(_FiberKey("tab_1"))), value.2._renderTabContent(in: context.child(_FiberKey("tab_2"))), value.3._renderTabContent(in: context.child(_FiberKey("tab_3")))])
    })
  }

  public static func buildBlock<C0, C1, C2, C3, C4>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> some TabContent<TabValue>
  where TabValue == C0.TabValue,
        C0: TabContent,
        C1: TabContent,
        C2: TabContent,
        C3: TabContent,
        C4: TabContent,
        C1.TabValue == C0.TabValue,
        C2.TabValue == C0.TabValue,
        C3.TabValue == C0.TabValue,
        C4.TabValue == C0.TabValue {
    _TupleTabContent<TabValue, (C0, C1, C2, C3, C4)>(value: (c0, c1, c2, c3, c4), renderer: { value, context in
      _tabFragment([value.0._renderTabContent(in: context.child(_FiberKey("tab_0"))), value.1._renderTabContent(in: context.child(_FiberKey("tab_1"))), value.2._renderTabContent(in: context.child(_FiberKey("tab_2"))), value.3._renderTabContent(in: context.child(_FiberKey("tab_3"))), value.4._renderTabContent(in: context.child(_FiberKey("tab_4")))])
    })
  }

  public static func buildBlock<C0, C1, C2, C3, C4, C5>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> some TabContent<TabValue>
  where TabValue == C0.TabValue,
        C0: TabContent,
        C1: TabContent,
        C2: TabContent,
        C3: TabContent,
        C4: TabContent,
        C5: TabContent,
        C1.TabValue == C0.TabValue,
        C2.TabValue == C0.TabValue,
        C3.TabValue == C0.TabValue,
        C4.TabValue == C0.TabValue,
        C5.TabValue == C0.TabValue {
    _TupleTabContent<TabValue, (C0, C1, C2, C3, C4, C5)>(value: (c0, c1, c2, c3, c4, c5), renderer: { value, context in
      _tabFragment([value.0._renderTabContent(in: context.child(_FiberKey("tab_0"))), value.1._renderTabContent(in: context.child(_FiberKey("tab_1"))), value.2._renderTabContent(in: context.child(_FiberKey("tab_2"))), value.3._renderTabContent(in: context.child(_FiberKey("tab_3"))), value.4._renderTabContent(in: context.child(_FiberKey("tab_4"))), value.5._renderTabContent(in: context.child(_FiberKey("tab_5")))])
    })
  }

  public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> some TabContent<TabValue>
  where TabValue == C0.TabValue,
        C0: TabContent,
        C1: TabContent,
        C2: TabContent,
        C3: TabContent,
        C4: TabContent,
        C5: TabContent,
        C6: TabContent,
        C1.TabValue == C0.TabValue,
        C2.TabValue == C0.TabValue,
        C3.TabValue == C0.TabValue,
        C4.TabValue == C0.TabValue,
        C5.TabValue == C0.TabValue,
        C6.TabValue == C0.TabValue {
    _TupleTabContent<TabValue, (C0, C1, C2, C3, C4, C5, C6)>(value: (c0, c1, c2, c3, c4, c5, c6), renderer: { value, context in
      _tabFragment([value.0._renderTabContent(in: context.child(_FiberKey("tab_0"))), value.1._renderTabContent(in: context.child(_FiberKey("tab_1"))), value.2._renderTabContent(in: context.child(_FiberKey("tab_2"))), value.3._renderTabContent(in: context.child(_FiberKey("tab_3"))), value.4._renderTabContent(in: context.child(_FiberKey("tab_4"))), value.5._renderTabContent(in: context.child(_FiberKey("tab_5"))), value.6._renderTabContent(in: context.child(_FiberKey("tab_6")))])
    })
  }

  public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> some TabContent<TabValue>
  where TabValue == C0.TabValue,
        C0: TabContent,
        C1: TabContent,
        C2: TabContent,
        C3: TabContent,
        C4: TabContent,
        C5: TabContent,
        C6: TabContent,
        C7: TabContent,
        C1.TabValue == C0.TabValue,
        C2.TabValue == C0.TabValue,
        C3.TabValue == C0.TabValue,
        C4.TabValue == C0.TabValue,
        C5.TabValue == C0.TabValue,
        C6.TabValue == C0.TabValue,
        C7.TabValue == C0.TabValue {
    _TupleTabContent<TabValue, (C0, C1, C2, C3, C4, C5, C6, C7)>(value: (c0, c1, c2, c3, c4, c5, c6, c7), renderer: { value, context in
      _tabFragment([value.0._renderTabContent(in: context.child(_FiberKey("tab_0"))), value.1._renderTabContent(in: context.child(_FiberKey("tab_1"))), value.2._renderTabContent(in: context.child(_FiberKey("tab_2"))), value.3._renderTabContent(in: context.child(_FiberKey("tab_3"))), value.4._renderTabContent(in: context.child(_FiberKey("tab_4"))), value.5._renderTabContent(in: context.child(_FiberKey("tab_5"))), value.6._renderTabContent(in: context.child(_FiberKey("tab_6"))), value.7._renderTabContent(in: context.child(_FiberKey("tab_7")))])
    })
  }

  public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> some TabContent<TabValue>
  where TabValue == C0.TabValue,
        C0: TabContent,
        C1: TabContent,
        C2: TabContent,
        C3: TabContent,
        C4: TabContent,
        C5: TabContent,
        C6: TabContent,
        C7: TabContent,
        C8: TabContent,
        C1.TabValue == C0.TabValue,
        C2.TabValue == C0.TabValue,
        C3.TabValue == C0.TabValue,
        C4.TabValue == C0.TabValue,
        C5.TabValue == C0.TabValue,
        C6.TabValue == C0.TabValue,
        C7.TabValue == C0.TabValue,
        C8.TabValue == C0.TabValue {
    _TupleTabContent<TabValue, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8), renderer: { value, context in
      _tabFragment([value.0._renderTabContent(in: context.child(_FiberKey("tab_0"))), value.1._renderTabContent(in: context.child(_FiberKey("tab_1"))), value.2._renderTabContent(in: context.child(_FiberKey("tab_2"))), value.3._renderTabContent(in: context.child(_FiberKey("tab_3"))), value.4._renderTabContent(in: context.child(_FiberKey("tab_4"))), value.5._renderTabContent(in: context.child(_FiberKey("tab_5"))), value.6._renderTabContent(in: context.child(_FiberKey("tab_6"))), value.7._renderTabContent(in: context.child(_FiberKey("tab_7"))), value.8._renderTabContent(in: context.child(_FiberKey("tab_8")))])
    })
  }

  public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8, C9>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> some TabContent<TabValue>
  where TabValue == C0.TabValue,
        C0: TabContent,
        C1: TabContent,
        C2: TabContent,
        C3: TabContent,
        C4: TabContent,
        C5: TabContent,
        C6: TabContent,
        C7: TabContent,
        C8: TabContent,
        C9: TabContent,
        C1.TabValue == C0.TabValue,
        C2.TabValue == C0.TabValue,
        C3.TabValue == C0.TabValue,
        C4.TabValue == C0.TabValue,
        C5.TabValue == C0.TabValue,
        C6.TabValue == C0.TabValue,
        C7.TabValue == C0.TabValue,
        C8.TabValue == C0.TabValue,
        C9.TabValue == C0.TabValue {
    _TupleTabContent<TabValue, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8, c9), renderer: { value, context in
      _tabFragment([value.0._renderTabContent(in: context.child(_FiberKey("tab_0"))), value.1._renderTabContent(in: context.child(_FiberKey("tab_1"))), value.2._renderTabContent(in: context.child(_FiberKey("tab_2"))), value.3._renderTabContent(in: context.child(_FiberKey("tab_3"))), value.4._renderTabContent(in: context.child(_FiberKey("tab_4"))), value.5._renderTabContent(in: context.child(_FiberKey("tab_5"))), value.6._renderTabContent(in: context.child(_FiberKey("tab_6"))), value.7._renderTabContent(in: context.child(_FiberKey("tab_7"))), value.8._renderTabContent(in: context.child(_FiberKey("tab_8"))), value.9._renderTabContent(in: context.child(_FiberKey("tab_9")))])
    })
  }
}

extension _ConditionalContent: TabContent where TrueContent: TabContent, FalseContent: TabContent,
  TrueContent.TabValue == FalseContent.TabValue {
  public typealias TabValue = TrueContent.TabValue
  public typealias Body = Never

  @_spi(Renderer) @MainActor public func _renderTabContent(in context: _RenderContext) -> _RenderNode {
    switch branch {
    case .trueContent(let box): return box.value._renderTabContent(in: context.child(_FiberKey("true")))
    case .falseContent(let box): return box.value._renderTabContent(in: context.child(_FiberKey("false")))
    }
  }
}

/// `if` without `else` in tab content keeps the tabs of its wrapped value.
extension Optional: TabContent where Wrapped: TabContent {
  public typealias TabValue = Wrapped.TabValue
  public typealias Body = Never

  @_spi(Renderer) @MainActor public func _renderTabContent(in context: _RenderContext) -> _RenderNode {
    switch self {
    case .some(let wrapped): return wrapped._renderTabContent(in: context)
    case .none: return _RenderNode.fragment()
    }
  }
}

