import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWeb

/// A tab's title read from an observable model (a language setting) must reach
/// the tab bar when the model changes.
@Suite
@MainActor
struct TabLabelObservationTests {
  @Observable final class Language { var greeting = "Início" }

  private struct Shell: View {
    let language: Language
    @State private var selection = "a"
    var body: some View {
      TabView(selection: $selection) {
        ForEach(["a", "b"], id: \.self) { tag in
          Tab(language.greeting + tag, systemImage: "circle", value: tag) { Text("page \(tag)") }
        }
      }
    }
  }

  private func labels(_ node: _RenderNode) -> [String] {
    var found: [String] = []
    func walk(_ node: _RenderNode) {
      if let label = node.attributes["data-tab-label"] { found.append(label) }
      for child in node.children { walk(child) }
    }
    walk(node)
    return found
  }

  @Test
  func tabTitlesFollowAnObservableModel() {
    let language = Language()
    let tree = FiberTree(Shell(language: language), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    #expect(labels(tree.renderNode).contains("Inícioa"))
    language.greeting = "Home"
    #expect(labels(tree.renderNode).contains("Homea"), Comment(rawValue: labels(tree.renderNode).joined(separator: ",")))
  }
}
