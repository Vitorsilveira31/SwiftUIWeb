import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A tab's content is built when the tab is first selected and stays mounted
/// afterwards, like SwiftUI's TabView; unvisited tabs cost a placeholder.
@Suite
@MainActor
struct TabViewLazyMountTests {
  private final class Builds: @unchecked Sendable { var names: [String] = [] }

  private struct Page: View {
    let name: String
    let builds: Builds
    @State private var taps = 0
    var body: some View {
      builds.names.append(name)
      return Button("\(name):\(taps)") { taps += 1 }
    }
  }

  private struct Root: View {
    let builds: Builds
    var policy = TabViewMountPolicy.keepVisited
    @State private var selection = "a"
    var body: some View {
      VStack {
        TabView(selection: $selection) {
          Tab("A", systemImage: "circle", value: "a") { Page(name: "a", builds: builds) }
          Tab("B", systemImage: "circle", value: "b") { Page(name: "b", builds: builds) }
          Tab("C", systemImage: "circle", value: "c") { Page(name: "c", builds: builds) }
        }
        .tabViewMountPolicy(policy)
        Button("go-a") { selection = "a" }
        Button("go-b") { selection = "b" }
        Button("go-c") { selection = "c" }
      }
    }
  }

  @Test
  func onlyTheSelectedTabIsBuiltUntilVisited() {
    let builds = Builds()
    let tree = FiberTree(Root(builds: builds), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    _ = tree.renderNode
    #expect(Set(builds.names) == ["a"])

    click("go-b", tree)
    #expect(labels(tree.renderNode).contains("b:0"))
    #expect(Set(builds.names) == ["a", "b"])
    #expect(!builds.names.contains("c"))
  }

  @Test
  func aVisitedTabKeepsItsStateWhenAnotherTabIsSelected() {
    let builds = Builds()
    let tree = FiberTree(Root(builds: builds), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    click("a:0", tree)
    #expect(labels(tree.renderNode).contains("a:1"))
    click("go-b", tree)
    click("go-a", tree)
    #expect(labels(tree.renderNode).contains("a:1"))
  }

  private struct DefaultPolicyRoot: View {
    let builds: Builds
    @State private var selection = "a"
    var body: some View {
      VStack {
        TabView(selection: $selection) {
          Tab("A", systemImage: "circle", value: "a") { Page(name: "a", builds: builds) }
          Tab("B", systemImage: "circle", value: "b") { Page(name: "b", builds: builds) }
          Tab("C", systemImage: "circle", value: "c") { Page(name: "c", builds: builds) }
          Tab("D", systemImage: "circle", value: "d") { Page(name: "d", builds: builds) }
        }
        Button("go-b") { selection = "b" }
        Button("go-c") { selection = "c" }
        Button("go-d") { selection = "d" }
      }
    }
  }

  @Test
  func theDefaultPolicyKeepsEveryVisitedTabWithItsState() {
    let builds = Builds()
    let tree = FiberTree(DefaultPolicyRoot(builds: builds), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    click("a:0", tree)                       // a: taps = 1
    click("go-b", tree)
    click("go-c", tree)
    click("go-d", tree)
    #expect(labels(tree.renderNode).contains("a:1"), "the first tab is still mounted after three others, as in SwiftUI")
    #expect(["b:0", "c:0", "d:0"].allSatisfy(labels(tree.renderNode).contains))
  }

  @Test
  func recentPolicyDropsOlderTabsFromTheTreeAndBuildsThemAgainWhenReopened() {
    let builds = Builds()
    let tree = FiberTree(Root(builds: builds, policy: .recent(2)), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    click("a:0", tree)                       // a: taps = 1
    #expect(labels(tree.renderNode).contains("a:1"))
    click("go-b", tree)
    click("go-c", tree)                      // a is now older than the last two tabs
    #expect(!labels(tree.renderNode).contains { $0.hasPrefix("a:") })
    #expect(labels(tree.renderNode).contains { $0.hasPrefix("c:") })
    click("go-a", tree)                      // reopened: built again
    #expect(labels(tree.renderNode).contains { $0.hasPrefix("a:") })
    #expect(!labels(tree.renderNode).contains { $0.hasPrefix("b:") })
    #expect(builds.names.filter { $0 == "a" }.count >= 2)
  }

  @Test
  func recentPolicyKeepsTheStateOfTabsWithinTheWindow() {
    let builds = Builds()
    let tree = FiberTree(Root(builds: builds, policy: .recent(2)), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    click("a:0", tree)
    click("go-b", tree)
    click("go-a", tree)                      // a and b are the last two: a keeps its state
    #expect(labels(tree.renderNode).contains("a:1"))
  }

  /// A page that logs its lifecycle, and a root whose own state re-renders the tab view without changing its selection.
  private struct LoggingPage: View {
    let name: String
    let builds: Builds
    @State private var taps = 0
    var body: some View {
      builds.names.append(name)
      return Button("\(name):\(taps)") { taps += 1 }
        .onAppear { builds.names.append("appear-\(name)") }
        .onDisappear { builds.names.append("disappear-\(name)") }
    }
  }

  private struct BumpingRoot: View {
    let builds: Builds
    @State private var selection = "a"
    @State private var bumps = 0
    var body: some View {
      VStack {
        Text("bumps:\(bumps)")
        TabView(selection: $selection) {
          Tab("A", systemImage: "circle", value: "a") { LoggingPage(name: "a", builds: builds) }
          Tab("B", systemImage: "circle", value: "b") { LoggingPage(name: "b", builds: builds) }
          Tab("C", systemImage: "circle", value: "c") { LoggingPage(name: "c", builds: builds) }
        }
        Button("go-a") { selection = "a" }
        Button("go-b") { selection = "b" }
        Button("go-c") { selection = "c" }
        Button("bump") { bumps += 1 }
      }
    }
  }

  /// Hidden tabs already built are kept as the Fiber holds them: a pass of the tab view builds the selected tab only.
  @Test
  func aPassOfTheTabViewBuildsOnlyTheSelectedTab() {
    let builds = Builds()
    let tree = FiberTree(BumpingRoot(builds: builds), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    tree._startLifecycle()
    _ = tree.renderNode
    click("a:0", tree)                       // a: taps = 1
    click("go-b", tree)
    click("go-c", tree)
    builds.names.removeAll()
    click("bump", tree)
    #expect(labels(tree.renderNode).contains("bumps:1"))
    #expect(builds.names.filter { !$0.contains("-") } == ["c"], "only the selected tab is built: \(builds.names)")
    #expect(["a:1", "b:0", "c:0"].allSatisfy(labels(tree.renderNode).contains), "hidden tabs keep their content and state")
  }

  /// A tab shown again is built in the pass that shows it, with its state; the tab it replaces disappears.
  @Test
  func aTabShownAgainIsBuiltWithItsStateAndTheOneItReplacesDisappears() {
    let builds = Builds()
    let tree = FiberTree(BumpingRoot(builds: builds), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    tree._startLifecycle()
    _ = tree.renderNode
    click("a:0", tree)
    click("go-b", tree)
    click("bump", tree)                      // a is hidden and kept, b is selected
    builds.names.removeAll()
    click("go-a", tree)
    #expect(builds.names.contains("a"), "the tab shown again is built: \(builds.names)")
    #expect(builds.names.contains("disappear-b"), "the tab it replaces disappears: \(builds.names)")
    #expect(builds.names.contains("appear-a"), "and the tab shown appears: \(builds.names)")
    #expect(labels(tree.renderNode).contains("a:1"))
  }

  private func click(_ label: String, _ tree: FiberTree) {
    guard let fiber = find(tree.root, label) else { Issue.record("missing \(label) in \(labels(tree.renderNode))"); return }
    tree.dispatch(event: "click", at: fiber.identity)
    _ = tree.renderNode
  }

  private func find(_ fiber: Fiber, _ label: String) -> Fiber? {
    if fiber.renderNode.attributes["data-control-kind"] == "button", labels(fiber.renderNode) == [label] { return fiber }
    for child in fiber.children { if let f = find(child, label) { return f } }
    return nil
  }

  private func labels(_ node: _RenderNode) -> [String] {
    if node.kind == .text, let text = node.text { return [text] }
    return node.children.flatMap(labels)
  }
}

/// The studio's structure: primary tabs from a ForEach plus grouped tabs in
/// TabSections, enum selection, driven by clicking the tab buttons in turn.
@Suite
@MainActor
struct TabViewLazyMountNavigationTests {
  private enum Section: String, CaseIterable, Hashable { case home, works, reviews, production, releases, results, skills, settings }
  private final class Rendered: @unchecked Sendable { var selection = Section.home }

  private struct Root: View {
    let rendered: Rendered
    @State private var selection = Section.home
    var body: some View {
      rendered.selection = selection
      return TabView(selection: $selection) {
        ForEach([Section.home, .works, .reviews, .production, .releases, .results], id: \.self) { section in
          Tab(section.rawValue, systemImage: "circle", value: section) { Text("content-\(section.rawValue)") }
        }
        TabSection("Knowledge") {
          Tab("skills", systemImage: "circle", value: Section.skills) { Text("content-skills") }
        }
        TabSection("Studio") {
          Tab("settings", systemImage: "circle", value: Section.settings) { Text("content-settings") }
        }
      }
      .tabViewStyle(.sidebarAdaptable)
    }
  }

  private func tabButton(_ label: String, in node: _RenderNode) -> _RenderNode? {
    if node.attributes["role"] == "tab", node.attributes["data-tab-label"] == label { return node }
    for child in node.children { if let found = tabButton(label, in: child) { return found } }
    return nil
  }

  private func visibleContent(_ node: _RenderNode) -> [String] {
    var out: [String] = []
    func walk(_ n: _RenderNode, hidden: Bool) {
      let hide = hidden || n.attributes["data-tab-hidden"] == "true"
      if !hide, n.kind == .text, let text = n.text, text.hasPrefix("content-") { out.append(text) }
      for child in n.children { walk(child, hidden: hide) }
    }
    walk(node, hidden: false)
    return out
  }

  @Test
  func everyTabButtonShowsItsOwnContentEvenWhenRevisited() throws {
    let rendered = Rendered()
    let tree = FiberTree(Root(rendered: rendered))
    defer { tree._dispose() }
    let order = ["home", "works", "reviews", "production", "releases", "results", "skills", "settings", "works", "home", "settings", "works"]
    for label in order {
      let button = try #require(tabButton(label, in: tree.renderNode), "tab \(label)")
      tree.dispatch(event: "click", on: button)
      let visible = visibleContent(tree.renderNode)
      #expect(rendered.selection.rawValue == label, "selection after \(label)")
      #expect(visible == ["content-\(label)"], "visible after \(label): \(visible)")
    }
  }
}
