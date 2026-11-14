import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
struct TabViewMobileSwitcherTests {
  @Test
  func sidebarContentKeepsIndependentStateAndActionsAcrossTabSelection() throws {
    struct SidebarCounter: View {
      let name: String
      @State(memberID: 137) private var count = 0
      var body: some View {
        Button("\(name): \(count)") { count += 1 }.accessibilityIdentifier(name)
      }
    }
    struct Root: View {
      @State private var selection = "home"
      var body: some View {
        TabView(selection: $selection) {
          Tab("Home", systemImage: "circle", value: "home") { Text("Home screen") }
          Tab("Saved", systemImage: "circle", value: "saved") { Text("Saved items") }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader { SidebarCounter(name: "header") }
        .tabViewSidebarFooter { SidebarCounter(name: "footer") }
        .tabViewSidebarBottomBar { SidebarCounter(name: "account") }
      }
    }
    let tree = FiberTree(Root())
    for name in ["header", "footer", "account"] {
      let button = try #require(findNode(tree.renderNode) { $0.attributes["data-testid"] == name })
      tree.dispatch(event: "click", on: button)
      _ = tree.update(Root())
      let updated = try #require(findNode(tree.renderNode) { $0.attributes["data-testid"] == name })
      #expect(updated.htmlDescription.contains("\(name): 1"))
    }
    let saved = try #require(findNode(tree.renderNode) { $0.attributes["role"] == "tab" && $0.attributes["data-tab-label"] == "Saved" })
    tree.dispatch(event: "click", on: saved)
    _ = tree.update(Root())
    for name in ["header", "footer", "account"] {
      let button = try #require(findNode(tree.renderNode) { $0.attributes["data-testid"] == name })
      #expect(button.htmlDescription.contains("\(name): 1"))
    }
  }

  @Test
  func adaptiveTabsEmitOneSidebarSurfaceWithMenuButtonAndBadgeSummary() throws {
    let tree = FiberTree(
      TabView(selection: .constant("home")) {
        Tab("Home", systemImage: "house", value: "home") { Text("Home screen") }
        Tab("Reviews", systemImage: "eye", value: "reviews") { Text("Reviews") }.badge(3)
        Tab("Production", systemImage: "waveform.path.ecg", value: "production") { Text("Jobs") }.badge("\u{2022}")
        TabSection("Library") {
          Tab("Saved", systemImage: "bookmark", value: "saved") { Text("Saved items") }.badge(2)
        }
      }
      .tabViewStyle(.sidebarAdaptable)
    )
    let tabView = try #require(findNode(tree.renderNode) { $0.classes.contains("tab-view") })
    #expect(tabView.attributes["data-tab-breakpoints"] == "767,1199")
    let sidebar = try #require(tabView.children.first { $0.attributes["data-tab-sidebar"] == "true" })
    let header = try #require(sidebar.children.first)
    #expect(header.attributes["data-tab-sidebar-header"] == "true")
    let tabList = try #require(sidebar.children.first { $0.attributes["role"] == "tablist" })
    #expect(tabList.classes == ["tab-list", "tab-sidebar-list"])

    let toggle = try #require(findNode(header) { $0.attributes["data-tab-sidebar-toggle"] == "true" })
    #expect(toggle.attributes["aria-controls"] == sidebar.attributes["id"])
    #expect(toggle.children.first?.attributes["data-symbol"] == "sidebar.left")

    let fab = try #require(tabView.children.first { $0.attributes["data-tab-mobile-toggle"] == "true" })
    let backdrop = try #require(tabView.children.first { $0.attributes["data-tab-mobile-backdrop"] == "true" })
    #expect(fab.attributes["aria-label"] == "Open app navigation")
    #expect(fab.attributes["aria-expanded"] == "false")
    #expect(fab.attributes["aria-controls"] == sidebar.attributes["id"])
    #expect(fab.children.compactMap { $0.attributes["data-symbol"] } == ["line.3.horizontal", "xmark"])
    // Numeric badges are summarized on the floating button; the activity dot is not a count.
    #expect(fab.attributes["data-badge"] == "5")
    #expect(fab.children.last?.classes.contains("tab-mobile-badge") == true)
    #expect(backdrop.attributes["hidden"] == "hidden")

    let production = try #require(findNode(tabList) { $0.attributes["data-tab-label"] == "Production" })
    #expect(production.attributes["data-badge-style"] == "dot")
    let dot = try #require(production.children.last)
    #expect(dot.attributes["data-badge-style"] == "dot")
    #expect(dot.attributes["aria-hidden"] == "true")
    #expect(dot.children.isEmpty)
    let reviews = try #require(findNode(tabList) { $0.attributes["data-tab-label"] == "Reviews" })
    #expect(reviews.children.last?.attributes["aria-label"] == "3")
  }

  @Test
  func sidebarPlacementsFollowTheShellStructure() throws {
    struct Root: View {
      var body: some View {
        TabView(selection: .constant("home")) {
          Tab("Home", systemImage: "house", value: "home") { Text("Home screen") }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarBottomBar { Text("Account") }
        .tabViewSidebarHeader {
          HStack {
            Image("logo.svg")
            Text("Studio")
          }
        }
        .tabViewSidebarFooter { Text("Actions") }
      }
    }
    let tree = FiberTree(Root())
    let sidebar = try #require(findNode(tree.renderNode) { $0.attributes["data-tab-sidebar"] == "true" })
    #expect(sidebar.children.map { $0.attributes["data-tab-sidebar-content"] ?? $0.attributes["role"] ?? "header" }
      == ["header", "tablist", "footer", "bottom-bar"])
    let toggle = try #require(findNode(sidebar) { $0.attributes["data-tab-sidebar-toggle"] == "true" })
    #expect(toggle.attributes["data-tab-has-logo"] == "true")
    let logo = try #require(toggle.children.first)
    #expect(logo.classes == ["tab-sidebar-toggle-logo"])
    #expect(logo.attributes["src"] == "logo.svg")
    #expect(logo.attributes["aria-hidden"] == "true")
    let tabView = try #require(findNode(tree.renderNode) { $0.classes.contains("tab-view") })
    #expect(tabView.attributes["data-tab-has-footer"] == "true")
    #expect(tabView.attributes["data-tab-has-bottom-bar"] == "true")
  }
}

private func findNode(_ node: _RenderNode, matching predicate: (_RenderNode) -> Bool) -> _RenderNode? {
  if predicate(node) { return node }
  for child in node.children {
    if let match = findNode(child, matching: predicate) { return match }
  }
  return nil
}
