import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite(.serialized)
@MainActor
struct ProjectedBindingObservationTests {
  @Observable final class Model {
    var selection: String? = nil
    var filter = "ALL"
    let names = ["A", "B"]
  }

  private struct Detail: View {
    @Binding var selection: String?
    @Binding var filter: String
    let names: [String]
    var body: some View {
      VStack {
        HStack {
          ForEach(names, id: \.self) { name in
            Button("Select \(name)") { selection = name; filter = name }
          }
        }
        if let selection { Text("Detail \(selection)") }
        else { Text("No selection") }
        Text("Filter \(filter)")
      }
    }
  }

  private struct Root: View {
    @State private var model = Model()
    var body: some View {
      VStack {
        Text("Library")
        Detail(
          selection: $model.selection,
          filter: $model.filter,
          names: model.names
        )
      }
    }
  }

  private struct Host: View {
    var body: some View { VStack { Root() } }
  }

  @Test func projectedBindingsTrackConditionalStructureAcrossRetainedPasses() {
    let tree = FiberTree(Host())
    for value in ["A", "B", "A", "B"] {
      guard let button = findButton("Select \(value)", in: tree.root) else {
        Issue.record("Missing selection button")
        return
      }
      tree.dispatch(event: "click", at: button.identity)
      let html = tree.renderNode.htmlDescription
      #expect(html.contains("Detail \(value)"))
      #expect(html.contains("Filter \(value)"))
      #expect(!html.contains("No selection"))
    }
    _ = tree.update(Host())
    #expect(tree.renderNode.htmlDescription.contains("Detail B"))
  }

  private func findButton(_ title: String, in fiber: Fiber) -> Fiber? {
    if fiber.renderNode.events["click"] != nil && text(fiber.renderNode) == title { return fiber }
    for child in fiber.children { if let found = findButton(title, in: child) { return found } }
    return nil
  }

  private func text(_ node: _RenderNode) -> String {
    (node.text ?? "") + node.children.map(text).joined()
  }
}
