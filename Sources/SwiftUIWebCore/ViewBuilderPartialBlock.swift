struct _ViewBuilderChildAppender {
  let append: @MainActor (_RenderContext, inout [_RenderNode], inout Int) -> Void
}

/// Carries a view from a nonisolated result-builder method into the main-actor closure that renders it. Only the
/// main actor ever reads `content`, so the unchecked transfer is the same single-threaded handoff as an
/// `_EnvironmentSnapshot`.
private struct _ViewBuilderChildBox<Content>: @unchecked Sendable {
  let content: Content
}

/// Concrete result of a multi-child ViewBuilder block. Its fixed generic shape
/// prevents Embedded Swift from having to specialize an arbitrarily deep type
/// chain. The ordered closures retain each concrete child until the existing
/// AnyView observation boundary and render as one sibling sequence.
public nonisolated struct _ViewBuilderContent<Components>: View {
  public typealias Body = Never

  let childAppenders: [_ViewBuilderChildAppender]

  nonisolated init(childAppenders: [_ViewBuilderChildAppender]) {
    self.childAppenders = childAppenders
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let fragment = _RenderNode.fragment()
    var index = 0
    for childAppender in childAppenders {
      childAppender.append(context, &fragment.children, &index)
    }
    return fragment
  }
}

nonisolated func _viewBuilderChildAppender<Content: View>(_ content: Content) -> _ViewBuilderChildAppender {
  let box = _ViewBuilderChildBox(content: content)
  return _ViewBuilderChildAppender { context, children, index in
    let childIndex = index
    index += 1
    let rendered = AnyView(box.content)._render(in: context.child(_FiberKey(childIndex)))
    // Keep an empty node in the structural Fiber sequence. It has no DOM
    // representation, but its slot prevents later siblings from changing
    // positional identity when this conditional component becomes visible.
    children.append(rendered)
  }
}
