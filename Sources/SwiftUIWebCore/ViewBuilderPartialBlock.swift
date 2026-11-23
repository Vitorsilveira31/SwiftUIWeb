/// Concrete result of a multi-child ViewBuilder block. Its fixed generic shape
/// prevents Embedded Swift from having to specialize an arbitrarily deep type
/// chain. Each child is erased when the block is formed, so what is compiled for a child's type is its erasure alone
/// (`AnyView.init`), and the children render as one sibling sequence in code that is compiled once.
public nonisolated struct _ViewBuilderContent<Components>: View {
  public typealias Body = Never

  let children: [AnyView]

  nonisolated init(children: [AnyView]) {
    self.children = children
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    _renderBuilderChildren(children, in: context)
  }
}

/// The children of a view builder block, each under its position in the block.
@inline(never)
@MainActor func _renderBuilderChildren(_ children: [AnyView], in context: _RenderContext) -> _RenderNode {
  let fragment = _RenderNode.fragment()
  var rendered: [_RenderNode] = []
  rendered.reserveCapacity(children.count)
  var index = 0
  for child in children {
    // An empty node stays in the structural Fiber sequence. It has no DOM
    // representation, but its slot prevents later siblings from changing
    // positional identity when this conditional component becomes visible.
    rendered.append(child._render(in: context.child(_FiberKey(index))))
    index += 1
  }
  fragment.children = rendered
  return fragment
}
