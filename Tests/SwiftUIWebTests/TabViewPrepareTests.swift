import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber

/// A tab the pointer rests on is built before it is selected (`tabPrepare`), hidden: its body runs, its lifecycle
/// (`onAppear`) waits for the selection, and selecting it shows the content already built.
@Suite
@MainActor
struct TabViewPrepareTests {
  private enum Pane: Hashable { case home, works }

  private final class Log { var bodies = 0; var appears = 0 }

  private struct Works: View {
    let log: Log
    var body: some View {
      log.bodies += 1
      return Text("works content").onAppear { log.appears += 1 }
    }
  }

  private struct Host: View {
    @State var selection = Pane.home
    let log: Log
    var body: some View {
      TabView(selection: $selection) {
        Tab("Home", systemImage: "house", value: Pane.home) { Text("home") }
        Tab("Works", systemImage: "book", value: Pane.works) { Works(log: log) }
      }
    }
  }

  @Test
  func aPreparedTabIsBuiltHiddenAndAppearsWhenSelected() throws {
    let log = Log()
    let tree = FiberTree(Host(log: log))
    #expect(log.bodies == 0)
    let works = try #require(findTab("Works", in: tree.renderNode))
    #expect(works.attributes["data-tab-prepare"] == "true")
    tree.dispatch(event: "tabPrepare", on: works)
    _ = tree.renderNode
    #expect(log.bodies == 1, "the prepared tab is built")
    #expect(log.appears == 0, "a hidden tab does not appear")
    #expect(tree.renderNode.htmlDescription.contains("works content"))
    let prepared = try #require(findTab("Works", in: tree.renderNode))
    #expect(prepared.attributes["data-tab-prepare"] == nil, "a built tab is not prepared again")
    #expect(panel("Works", in: tree.renderNode)?.attributes["data-tab-prepared"] == "true", "its hidden panel is laid out")

    tree.dispatch(event: "click", on: prepared)
    _ = tree.renderNode
    #expect(log.appears == 1, "selecting it runs its lifecycle")
    #expect(panel("Works", in: tree.renderNode)?.attributes["data-tab-prepared"] == nil, "a panel shown once is no longer only prepared")
    let selected = try #require(findTab("Home", in: tree.renderNode))
    #expect(selected.attributes["data-tab-prepare"] == nil, "the tab left behind is built already")
  }

  /// The panel of a tab never built says so (`data-tab-unbuilt`), so the host keeps the panel on screen when its button
  /// is clicked instead of showing the empty placeholder; a tab built, prepared or selected does not.
  @Test
  func onlyAPanelNeverBuiltIsMarkedUnbuilt() throws {
    let tree = FiberTree(Host(log: Log()))
    #expect(panel("Works", in: tree.renderNode)?.attributes["data-tab-unbuilt"] == "true")
    #expect(panel("Home", in: tree.renderNode)?.attributes["data-tab-unbuilt"] == nil, "the selected tab is built")

    let works = try #require(findTab("Works", in: tree.renderNode))
    tree.dispatch(event: "tabPrepare", on: works)
    _ = tree.renderNode
    #expect(panel("Works", in: tree.renderNode)?.attributes["data-tab-unbuilt"] == nil, "a prepared tab is built")

    tree.dispatch(event: "click", on: try #require(findTab("Works", in: tree.renderNode)))
    _ = tree.renderNode
    #expect(panel("Home", in: tree.renderNode)?.attributes["data-tab-unbuilt"] == nil, "a tab left behind was built")
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
