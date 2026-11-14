import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber

/// A tab whose pushed screen asks for `toolbar(.hidden, for: .tabBar)` hides the tab bar as soon as it is selected,
/// whether it was built by the selection or before it, hidden, when its button was pressed (`tabPrepare`). Built
/// hidden, its panel says so (`data-tab-hides-bar`): the host does not show it before the publication that removes the bar.
@Suite
@MainActor
struct TabViewHiddenBarSelectionTests {
  private struct Host: View {
    @State private var selection = 0
    var body: some View {
      TabView(selection: $selection) {
        Tab("Home", systemImage: "house", value: 0) { Text("home") }
        Tab("Hidden bar", systemImage: "rectangle.stack", value: 1) {
          NavigationStack(path: .constant(Self.pushed())) {
            Text("Hidden bar root")
          }
          .navigationDestination(for: Int.self) { _ in
            Text("Pushed screen").toolbar(.hidden, for: .tabBar)
          }
        }
      }
    }

    static func pushed() -> NavigationPath {
      var path = NavigationPath()
      path.append(1)
      return path
    }
  }

  @Test
  func selectingTheTabHidesTheTabBar() throws {
    let tree = FiberTree(Host())
    _expectTrue(tree.renderNode.htmlDescription.contains("tab-list"))
    tree.dispatch(event: "click", on: try #require(findTab("Hidden bar", in: tree.renderNode)))
    let html = tree.renderNode.htmlDescription
    _expectTrue(html.contains("Pushed screen"))
    _expectFalse(html.contains("tab-list"))
  }

  @Test
  func selectingAPreparedTabHidesTheTabBar() throws {
    let tree = FiberTree(Host())
    #expect(panel("Hidden bar", in: tree.renderNode)?.attributes["data-tab-hides-bar"] == nil, "a tab never built is not marked")
    tree.dispatch(event: "tabPrepare", on: try #require(findTab("Hidden bar", in: tree.renderNode)))
    _expectTrue(tree.renderNode.htmlDescription.contains("tab-list"), "a hidden tab does not hide the bar")
    #expect(panel("Hidden bar", in: tree.renderNode)?.attributes["data-tab-hides-bar"] == "true")
    #expect(panel("Home", in: tree.renderNode)?.attributes["data-tab-hides-bar"] == nil)
    tree.dispatch(event: "click", on: try #require(findTab("Hidden bar", in: tree.renderNode)))
    let html = tree.renderNode.htmlDescription
    _expectTrue(html.contains("Pushed screen"))
    _expectFalse(html.contains("tab-list"))
    _expectFalse(html.contains("data-tab-hides-bar"), "the selected panel is shown")
  }
}

private func findTab(_ label: String, in node: _RenderNode) -> _RenderNode? {
  if node.attributes["role"] == "tab", node.attributes["data-tab-label"] == label { return node }
  for child in node.children {
    if let found = findTab(label, in: child) { return found }
  }
  return nil
}

private func panel(_ label: String, in node: _RenderNode) -> _RenderNode? {
  guard let tab = findTab(label, in: node), let id = tab.attributes["aria-controls"] else { return nil }
  func find(_ node: _RenderNode) -> _RenderNode? {
    if node.attributes["role"] == "tabpanel", node.attributes["id"] == id { return node }
    for child in node.children { if let found = find(child) { return found } }
    return nil
  }
  return find(node)
}
