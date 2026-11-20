import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// The sidebar toggle of a NavigationSplitView, as on iPad: it hides the sidebar and shows it again, writing the
/// `columnVisibility` binding when the split view has one.
@Suite
@MainActor
struct NavigationSplitViewSidebarToggleTests {
  @Test
  func theToggleHidesTheSidebarAndShowsItAgain() throws {
    let tree = FiberTree(
      NavigationSplitView {
        List { Text("Truck") }.navigationTitle("Food Truck")
      } detail: {
        Text("Detail")
      }
    )
    defer { tree._dispose() }
    // Shown: the sidebar's header holds its title; the toggle is the split view's last child, which the stylesheet
    // places at the top of the sidebar.
    var sidebar = try #require(column("sidebar", in: tree.renderNode))
    let header = try #require(sidebar.children.first)
    #expect(header.classes.contains("navigation-sidebar-header"))
    #expect(texts(header) == ["Food Truck"])
    #expect(sidebar.attributes["data-column-hidden"] == nil)
    var toggle = try #require(findSplit(in: tree.renderNode)?.children.last)
    #expect(toggle.classes.contains("navigation-sidebar-toggle"))
    #expect(toggle.attributes["aria-expanded"] == "true")
    let detailChildren = try #require(column("detail", in: tree.renderNode)).children.count

    tree.dispatch(event: "click", value: "", on: toggle)
    var split = tree.renderNode
    sidebar = try #require(column("sidebar", in: split))
    #expect(sidebar.attributes["data-column-hidden"] == "true")
    #expect(findSplit(in: split)?.attributes["data-sidebar-hidden"] == "true")
    // Hidden: the same toggle (now at the detail's bar), the detail's children unchanged so its views are kept, and the
    // render the toggle caused names the columns for the view transition that moves them.
    let detail = try #require(column("detail", in: split))
    #expect(detail.children.count == detailChildren)
    toggle = try #require(findSplit(in: split)?.children.last)
    #expect(toggle.classes.contains("navigation-sidebar-toggle"))
    #expect(toggle.attributes["aria-expanded"] == "false")
    #expect(sidebar.styles["view-transition-name"] == "navigation-split-sidebar")
    #expect(detail.styles["view-transition-name"] == "navigation-split-detail")

    tree.dispatch(event: "click", value: "", on: toggle)
    split = tree.renderNode
    sidebar = try #require(column("sidebar", in: split))
    #expect(sidebar.attributes["data-column-hidden"] == nil)
    #expect(findSplit(in: split)?.attributes["data-sidebar-hidden"] == nil)
    #expect(find("navigation-sidebar-header", in: sidebar) != nil)
  }

  @Test
  func onlyTheTogglesRenderNamesTheColumnsForATransition() throws {
    let tree = FiberTree(Counter())
    defer { tree._dispose() }
    let toggle = try #require(find("navigation-sidebar-toggle", in: tree.renderNode))
    tree.dispatch(event: "click", value: "", on: toggle)
    #expect(column("detail", in: tree.renderNode)?.styles["view-transition-name"] != nil)
    // Another change in the page renders the split view again without the names: no transition.
    let increment = try #require(button(labeled: "0", in: tree.root))
    tree.dispatch(event: "click", at: increment.identity)
    #expect(texts(tree.renderNode).contains("1"))
    #expect(column("detail", in: tree.renderNode)?.styles["view-transition-name"] == nil)
  }

  @Test
  func theToggleWritesTheColumnVisibilityBinding() throws {
    let tree = FiberTree(BoundSplit())
    defer { tree._dispose() }
    #expect(texts(tree.renderNode).contains("visibility: automatic"))
    let toggle = try #require(find("navigation-sidebar-toggle", in: tree.renderNode))
    tree.dispatch(event: "click", value: "", on: toggle)
    #expect(texts(tree.renderNode).contains("visibility: detailOnly"))
    let shown = try #require(find("navigation-sidebar-toggle", in: tree.renderNode))
    tree.dispatch(event: "click", value: "", on: shown)
    #expect(texts(tree.renderNode).contains("visibility: all"))
  }

  @Test
  func aHiddenSidebarLeavesNoTrackInTheGrid() {
    // Food Truck sizes its sidebar: hidden, the detail took the sidebar's 200-point track.
    let html = StaticHTMLFiberRenderer().render(
      NavigationSplitView(columnVisibility: .constant(.detailOnly)) {
        List { Text("Sidebar") }.navigationSplitViewColumnWidth(min: 200, ideal: 200)
      } detail: {
        Text("Detail")
      }
    )
    // No track for the sidebar: the stylesheet gives a `detailOnly` split view one track for the detail.
    #expect(!html.contains("minmax(200px"), "\(html)")
    #expect(html.contains("data-column-visibility=\"detailOnly\""), "\(html)")
  }

  @Test
  func aSidebarWithoutATitleHasAHeaderWithTheToggleAlone() throws {
    let html = StaticHTMLFiberRenderer().render(
      NavigationSplitView { Text("Sidebar") } detail: { Text("Detail") }
    )
    #expect(html.contains("navigation-sidebar-header"))
    #expect(html.contains("aria-label=\"Hide Sidebar\""))
    #expect(!html.contains("navigation-sidebar-title"))
    #expect(!html.contains("data-sidebar-title"))
  }

  private struct Counter: View {
    @State var count = 0
    var body: some View {
      NavigationSplitView {
        Text("Sidebar")
      } detail: {
        Button("\(count)") { count += 1 }
      }
    }
  }

  private struct BoundSplit: View {
    @State var visibility = NavigationSplitViewVisibility.automatic
    var body: some View {
      NavigationSplitView(columnVisibility: $visibility) {
        Text("Sidebar")
      } detail: {
        Text("visibility: \(visibility._attributeValue)")
      }
    }
  }

  private func button(labeled label: String, in fiber: Fiber) -> Fiber? {
    if fiber.renderNode.attributes["data-control-kind"] == "button", texts(fiber.renderNode) == [label] { return fiber }
    for child in fiber.children { if let found = button(labeled: label, in: child) { return found } }
    return nil
  }

  private func findSplit(in node: _RenderNode) -> _RenderNode? { find("navigation-split-view", in: node) }

  private func column(_ name: String, in node: _RenderNode) -> _RenderNode? {
    if node.attributes["data-navigation-column"] == name { return node }
    for child in node.children { if let found = column(name, in: child) { return found } }
    return nil
  }

  private func find(_ className: String, in node: _RenderNode) -> _RenderNode? {
    if node.classes.contains(className) { return node }
    for child in node.children { if let found = find(className, in: child) { return found } }
    return nil
  }

  private func texts(_ node: _RenderNode) -> [String] {
    if node.kind == .text, let text = node.text { return [text] }
    return node.children.flatMap(texts)
  }
}
