import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@MainActor
struct PickerLazyContainerTests {
  @Test func optionsRemainEagerInsideLazyGrid() {
    var context = _RenderContext()
    context.lazyCollectionsEnabled = true
    let view = LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))]) {
      Picker("Status", selection: .constant("B")) {
        ForEach(["A", "B", "C"], id: \.self) { Text($0).tag($0) }
      }
    }
    let node = view._render(in: context)
    let options = descendants(node).filter {
      if case .element("option") = $0.kind { return true }
      return false
    }
    #expect(options.map { $0.attributes["value"] } == ["A", "B", "C"])
    #expect(options.filter { $0.attributes["selected"] != nil }.map { $0.attributes["value"] } == ["B"])
  }

  private func descendants(_ node: _RenderNode) -> [_RenderNode] {
    [node] + node.children.flatMap(descendants)
  }
}
