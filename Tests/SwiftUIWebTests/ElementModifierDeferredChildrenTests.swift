import Testing
@testable import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebCore

/// `_modifyElement` hands the owner's token and key to the copy of the element a modifier wraps (see
/// `ElementModifierOwnerTests`). An element whose children are deferred (`_RenderStaging`) may have them rendered by the
/// modifier itself, when it reads them before it copies the element: the copy then holds the rendered children, not the
/// deferred ones, and is still the content the owner returned.
@Suite(.serialized)
@MainActor
struct ElementModifierDeferredChildrenTests {
  private func element() -> _RenderNode {
    let node = _RenderNode.element("div")
    node._deferChildren(_RenderStaging.defer_(building: { [.text("one"), .text("two")] }))
    node._renderOwnerToken = 42
    node.key = _FiberKey("row")
    return node
  }

  private func content(of wrapper: _RenderNode) -> _RenderNode? {
    wrapper._children.first { $0.kind == .element("div") && $0.classes != wrapper.classes }
  }

  @Test
  func theCopyKeepsTheOwnerWhenTheModifierRendersTheDeferredChildren() {
    let node = element()
    _modifyElement(node) { element in
      // A modifier that reads what it wraps (a decorated layer's context) renders the children first.
      #expect(element.children.count == 2)
      _semanticWrap(element, kind: "aspect")
    }
    let copy = content(of: node)
    #expect(node._renderOwnerToken == nil, "the wrapper no longer stands for the owner")
    #expect(copy?._renderOwnerToken == 42, "the content it holds does")
    #expect(copy?.key == _FiberKey("row"))
    #expect(copy?.children.compactMap(\.text) == ["one", "two"])
  }

  @Test
  func theCopyKeepsTheOwnerWhenTheChildrenStayDeferred() {
    let node = element()
    _modifyElement(node) { _semanticWrap($0, kind: "aspect") }
    let copy = content(of: node)
    #expect(node._renderOwnerToken == nil)
    #expect(copy?._renderOwnerToken == 42)
    #expect(copy?.key == _FiberKey("row"))
    // The copy shares the deferred children; reading them renders them (and leaves no job behind for the next test).
    #expect(copy?.children.compactMap(\.text) == ["one", "two"])
  }
}
