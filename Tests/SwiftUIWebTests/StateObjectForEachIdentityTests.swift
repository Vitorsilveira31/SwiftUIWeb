import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite(.serialized)
@MainActor
struct StateObjectForEachIdentityTests {
  private final class RowModel: ObservableObject {
    let id: String
    var count = 0

    init(id: String) { self.id = id }

    func increment() {
      count += 1
      objectWillChange.send()
    }
  }

  private struct StatefulRow: View {
    @StateObject private var model: RowModel

    init(id: String) {
      _model = StateObject(wrappedValue: RowModel(id: id))
    }

    var body: some View {
      Button("\(model.id):\(model.count)") { model.increment() }
    }
  }

  private struct Root: View {
    let ids: [String]

    var body: some View {
      VStack {
        Text("head")
        ForEach(ids, id: \.self) { id in StatefulRow(id: id) }
        Text("tail")
      }
    }
  }

  private struct ConditionalRoot: View {
    let showsLeadingRow: Bool

    var body: some View {
      VStack {
        if showsLeadingRow { StatefulRow(id: "X") }
        StatefulRow(id: "A")
      }
    }
  }

  @Test
  func stateObjectBelongsToTheChildWhenItsParentInsertsAnEarlierSibling() async {
    let tree = FiberTree(ConditionalRoot(showsLeadingRow: false))
    guard let original = button("A:0", in: tree.root) else {
      Issue.record("The original stateful row should render")
      return
    }

    tree.dispatch(event: "click", at: original.identity)
    await _settleObservedRefreshes()
    _ = tree.renderNode
    #expect(button("A:1", in: tree.root) != nil)

    _ = tree.update(ConditionalRoot(showsLeadingRow: true))
    #expect(buttonLabels(in: tree.root.renderNode) == ["X:0", "A:1"])
  }

  @Test
  func stateObjectBelongsToKeyedRowWhenItemsAreInsertedBeforeIt() async {
    let tree = FiberTree(Root(ids: ["A", "B"]))
    guard let originalB = button("B:0", in: tree.root) else {
      Issue.record("ForEach should render row B")
      return
    }

    tree.dispatch(event: "click", at: originalB.identity)
    await _settleObservedRefreshes()
    _ = tree.renderNode
    #expect(button("B:1", in: tree.root) != nil)

    _ = tree.update(Root(ids: ["X", "A", "B"]))
    let labels = buttonLabels(in: tree.root.renderNode)
    #expect(labels == ["X:0", "A:0", "B:1"])

    guard let updatedB = button("B:1", in: tree.root) else {
      Issue.record("The retained row should keep its updated action")
      return
    }
    tree.dispatch(event: "click", at: updatedB.identity)
    await _settleObservedRefreshes()
    _ = tree.renderNode
    #expect(button("B:2", in: tree.root) != nil)
  }

  private func button(_ label: String, in fiber: Fiber) -> Fiber? {
    if fiber.renderNode.events["click"] != nil,
       buttonLabels(in: fiber.renderNode).contains(label) {
      return fiber
    }
    for child in fiber.children {
      if let match = button(label, in: child) { return match }
    }
    return nil
  }

  private func buttonLabels(in node: _RenderNode) -> [String] {
    var labels: [String] = []
    if node.events["click"] != nil { labels.append(text(in: node)) }
    for child in node.children { labels.append(contentsOf: buttonLabels(in: child)) }
    return labels
  }

  private func text(in node: _RenderNode) -> String {
    (node.text ?? "") + node.children.map(text(in:)).joined()
  }
}
