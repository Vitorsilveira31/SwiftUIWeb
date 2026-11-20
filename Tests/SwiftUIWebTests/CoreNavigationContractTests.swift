import Testing
import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite
@MainActor
struct CoreNavigationContractTests {
  private struct InheritingTabStyle: TabViewStyle {}

  private struct DefaultHistoryAdapter: NavigationHistoryAdapter {
    func apply(_ operation: NavigationHistoryOperation) { _ = operation }
  }

  private final class TabHistoryRecorder: NavigationHistoryAdapter {
    var defaults: [String: String] = [:]
    var observers: [String: (String) -> Void] = [:]
    var updates: [(String, String)] = []

    func apply(_ operation: NavigationHistoryOperation) { _ = operation }

    func _setTabDefault(namespace: String, tag: String) {
      defaults[namespace] = tag
    }

    func _observeTab(namespace: String, callback: @escaping (String) -> Void) {
      observers[namespace] = callback
    }

    func _updateTab(namespace: String, tag: String) {
      updates.append((namespace, tag))
    }
  }

  @Test
  func navigationPathSupportsReplacementRemovalSnapshotsAndStableHashing() {
    var path = NavigationPath(["catalog", "detail"])
    #expect(path.count == 2)
    #expect(!path.isEmpty)
    #expect(path._historyPathDescription() == "/catalog/detail")

    let samePath = NavigationPath(["catalog", "detail"])
    #expect(path == samePath)
    #expect(Set([path, samePath]).count == 1)
    #expect(path._historySnapshot() == path)

    path.replaceLast("review")
    #expect(path._historyPathDescription() == "/catalog/review")
    path.replace("settings")
    #expect(path.count == 1)
    #expect(path._historyPathDescription() == "/settings")

    path.removeLast(0)
    #expect(path.count == 1)
    path.removeLast(20)
    #expect(path.isEmpty)
    path.replaceLast("login")
    #expect(path._historyPathDescription() == "/login")
    path.removeAll()
    #expect(path._historyPathDescription() == "/")
    #expect(path.isEmpty)
  }

  @Test
  func defaultHistoryAdapterProvidesNeutralFallbacksAndTabTokens() throws {
    let adapter = DefaultHistoryAdapter()
    let path = NavigationPath(["one", "two"])
    #expect(adapter.path(for: NavigationPath()) == "/")
    #expect(adapter.path(for: path) == "/one/two")
    #expect(adapter._scope("nested").path(for: path) == "/one/two")
    adapter.update(path)
    adapter.observe { _ in Issue.record("Default history adapter does not install observers") }
    adapter._updateTab(namespace: "tabs", tag: "home")
    adapter._observeTab(namespace: "tabs") { _ in Issue.record("Default history adapter does not observe tabs") }
    adapter._setTabDefault(namespace: "tabs", tag: "home")

    let tabPath = NavigationPath(["__tab:tabs", "home"])
    let components = try #require(_tabHistoryComponents(tabPath))
    #expect(components.namespace == "tabs")
    #expect(components.tag == "home")
    #expect(_tabHistoryComponents(NavigationPath(["tabs"])) == nil)
    #expect(_tabHistoryNamespaceToken("tabs") == _tabHistoryNamespaceToken("tabs"))
    #expect(!_tabHistoryNamespaceToken("tabs").isEmpty)
  }

  @Test
  func modernTabAndSectionInitializerSpellingsRenderTheirRolesAndLabels() {
    #expect(DefaultTabViewStyle()._swiftUIWebTabViewStyle == "automatic")
    #expect(SidebarAdaptableTabViewStyle()._swiftUIWebTabViewStyle == "sidebar-adaptable")
    let profileTitle = "Profile"
    let tabs = TabView(selection: Binding<String>.constant("home")) {
      Tab("Home", systemImage: "house", value: "home") { Text("Home screen") }
      Tab(profileTitle[...], systemImage: "circle", value: "profile") { Text("Profile screen") }
      Tab(value: "custom", content: { Text("Custom screen") }) {
        Label("Custom", systemImage: "star")
      }
      Tab(value: "search", role: .search) { Text("Search screen") }
      Tab(value: "labeled-search", role: .search, content: { Text("Labeled search") }) {
        Label("Find", systemImage: "magnifyingglass")
      }
      TabSection("Library"[...]) {
        Tab("Downloads", systemImage: "circle", value: "downloads") { Text("Downloads screen") }
      }
      TabSection(content: {
        Tab("Account", systemImage: "circle", value: "account") { Text("Account screen") }
      }, header: { Text("Account section") })
      TabSection(content: {
        Tab("Help", systemImage: "circle", value: "help") { Text("Help screen") }
      }, header: { Text("More") })
      TabSection {
        Tab("About", systemImage: "circle", value: "about") { Text("About screen") }
      }
    }
    let html = StaticHTMLFiberRenderer().render(tabs)

    #expect(html.contains("data-tab-label=\"Home\""))
    #expect(html.contains("data-tab-system-image=\"house\""))
    #expect(html.contains("data-tab-label=\"Profile\""))
    #expect(html.contains("data-tab-label=\"Custom\""), "an icon's fallback glyph is not part of the tab title")
    #expect(html.contains("data-tab-role=\"search\""))
    #expect(html.contains("data-tab-section-title=\"Library\""))
    #expect(html.contains("data-tab-section-title=\"Account section\""))
    #expect(html.contains("data-tab-section-title=\"More\""))
    #expect(!html.contains("data-tab-section-title=\"\""))
    // Only the selected tab's content is built; unvisited tabs keep their
    // label/icon for the tab bar but render no content (lazy mounting).
    #expect(html.contains("Home screen"))
    #expect(!html.contains("Downloads screen"))
    #expect(!html.contains("About screen"))

    var customization = TabViewCustomization()
    customization.hiddenTabIdentifiers = ["settings"]
    #expect(customization.hiddenTabs == ["settings"])
    #expect(customization.hiddenTabIDs == ["settings"])
    customization.hiddenTabIDs = ["search"]
    #expect(customization.hiddenTabIdentifiers == ["search"])
    customization.tabOrder = ["search", "home"]
    #expect(customization.order == ["search", "home"])
    #expect(customization.tabOrder == ["search", "home"])

    #expect(TabViewCustomization(_storageValue: "").hiddenTabs.isEmpty)
    #expect(TabViewCustomization(_storageValue: "|").order.isEmpty)
    let persistent = TabViewCustomization(
      hiddenTabs: ["with,comma", "with|separator", "with\\slash"],
      order: ["second", "first,with-comma"]
    )
    #expect(TabViewCustomization(_storageValue: persistent._storageValue) == persistent)
  }

  @Test
  func tabLabelsUseAccessibleFallbackAndCustomStylesInheritAutomatic() throws {
    let tree = FiberTree(TabView(selection: .constant("accessible")) {
      Tab(value: "accessible", content: { Text("Accessible panel") }) {
        HTMLElement(tag: "span", attributes: ["aria-label": "Accessible tab"]) { EmptyView() }
      }
      Tab(value: "empty", content: { Text("Empty label panel") }, label: { EmptyView() })
    }.tabViewStyle(InheritingTabStyle()))

    let accessible = try #require(findNode(tree.renderNode) {
      $0.attributes["role"] == "tab" && $0.attributes["data-tab-label"] == "Accessible tab"
    })
    let fallback = try #require(findNode(tree.renderNode) {
      $0.attributes["role"] == "tab" && $0.attributes["data-tab-label"] == "Tab"
    })
    #expect(accessible.attributes["data-tab-label"] == "Accessible tab")
    #expect(fallback.attributes["data-tab-label"] == "Tab")
    #expect(tree.renderNode.attributes["data-tab-style"] == "automatic")
  }

  @Test
  func enumBackedTabsSelectTheirTypedValueAndSidebarStyleIsSemantic() throws {
    enum Destination: Hashable {
      case inbox
      case archive
    }
    struct Root: View {
      @State var selection = Destination.inbox

      var body: some View {
        TabView(selection: $selection) {
          Tab("Inbox", systemImage: "circle", value: Destination.inbox) { Text("Inbox panel") }
          Tab("Archive", systemImage: "circle", value: Destination.archive) { Text("Archive panel") }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization(.constant(TabViewCustomization(order: [
          fiberKeyDescription(_FiberKey(Destination.archive)),
          fiberKeyDescription(_FiberKey(Destination.inbox))
        ])))
      }
    }

    let root = Root()
    let tree = FiberTree(root)
    let tabView = try #require(findNode(tree.renderNode) { $0.classes.contains("tab-view") })
    #expect(tabView.attributes["data-tab-style"] == "sidebar-adaptable")
    #expect(tabView.attributes["data-tab-breakpoints"] == "767,1199")
    #expect(findNode(tabView, where: { $0.classes.contains("tab-sidebar-header") }) != nil)

    let archive = try #require(findNode(tree.renderNode) {
      $0.attributes["role"] == "tab" && $0.attributes["data-tab-label"] == "Archive"
    })
    #expect(archive.attributes["data-tab-index"] == "0")
    tree.dispatch(event: "click", on: archive)
    _ = tree.update(root)
    #expect(root.selection == .archive)
    #expect(tree.renderNode.htmlDescription.contains("Archive panel"))
  }

  @Test
  func columnWidthModifierSizesTheSplitViewTrack() {
    let html = StaticHTMLFiberRenderer().render(
      NavigationSplitView {
        List { Text("Sidebar") }.navigationSplitViewColumnWidth(min: 200, ideal: 220)
      } detail: {
        Text("Detail")
      }
    )
    #expect(html.contains("grid-template-columns: minmax(200px, 220px) minmax(0, 1fr)"), "\(html)")
    let fixed = StaticHTMLFiberRenderer().render(
      NavigationSplitView {
        List { Text("Sidebar") }.navigationSplitViewColumnWidth(260)
      } detail: {
        Text("Detail")
      }
    )
    #expect(fixed.contains("grid-template-columns: minmax(260px, 260px) minmax(0, 1fr)"), "\(fixed)")
  }

  @Test
  func splitNavigationHonorsTwoAndThreeColumnVisibilityModes() {
    let twoColumns = StaticHTMLFiberRenderer().render(
      NavigationSplitView(columnVisibility: .constant(.detailOnly)) {
        Text("Two-column sidebar")
      } detail: {
        Text("Two-column detail")
      }
    )
    #expect(twoColumns.contains("data-column-count=\"2\""))
    #expect(twoColumns.contains("data-navigation-column=\"sidebar\""))
    #expect(twoColumns.contains("data-navigation-column=\"detail\""))
    #expect(twoColumns.contains("data-column-hidden=\"true\""))

    let threeColumns = StaticHTMLFiberRenderer().render(
      NavigationSplitView(columnVisibility: .constant(.detailOnly)) {
        Text("Sidebar")
      } content: {
        Text("Content")
      } detail: {
        Text("Detail")
      }
    )
    #expect(threeColumns.contains("data-column-count=\"3\""))
    #expect(threeColumns.contains("role=\"complementary\""))
    #expect(threeColumns.contains("role=\"region\""))
    #expect(threeColumns.contains("role=\"main\""))
    #expect(threeColumns.contains("data-column-visibility=\"detailOnly\""))

    let doubleColumn = StaticHTMLFiberRenderer().render(
      NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
        Text("Double sidebar")
      } content: {
        Text("Double middle")
      } detail: {
        Text("Double detail")
      }
    )
    #expect(doubleColumn.contains("data-column-visibility=\"doubleColumn\""))
    #expect(doubleColumn.contains("data-column-hidden=\"true\""))

    let convenienceColumns = StaticHTMLFiberRenderer().render(
      NavigationSplitView { Text("Convenience sidebar") } detail: { Text("Convenience detail") }
    )
    #expect(convenienceColumns.contains("data-column-count=\"2\""))
    #expect(convenienceColumns.contains("Convenience sidebar"))
    #expect(convenienceColumns.contains("Convenience detail"))
  }

  @Test
  func viewsWrittenInAToolbarWithoutAnItemAreItemsOfTheirOwn() throws {
    // Food Truck's Orders: `.toolbar { NavigationLink(...); Button(...) }`. Without items the two views were laid out
    // as screens of the stack.
    let tree = FiberTree(
      NavigationStack {
        Text("Orders")
          .toolbar {
            Button("Details") {}
            Button("Complete") {}
          }
      }
    )
    let stack = try #require(findNode(tree.renderNode) { $0.classes.contains("navigation-stack") })
    func items(in node: _RenderNode) -> [_RenderNode] {
      node.classes.contains("toolbar-item") ? [node] : node.children.flatMap(items(in:))
    }
    let items = items(in: stack)
    #expect(items.count == 2)
    #expect(items.allSatisfy { $0.attributes["data-toolbar-placement"] == "automatic" })
    #expect(items.map(\.htmlDescription).joined().contains("Details"))
    #expect(!stack.children.contains { $0.classes.contains("push-button") })
  }

  @Test
  func integerTabsAndMultipleNavigationToolbarsRouteThroughTheirBindings() throws {
    struct Root: View {
      @State var selection = 0

      var body: some View {
        NavigationStack {
          VStack {
            Text("Home")
              .toolbar { ToolbarItem(placement: .topBarLeading) { Text("Back") } }
            Text("Inbox")
              .toolbar { ToolbarItem(placement: .topBarTrailing) { Text("Compose") } }
            TabView(selection: $selection) {
              Tab("Home", systemImage: "circle", value: 0) { Text("Home panel") }
              Tab("Inbox", systemImage: "circle", value: 1) { Text("Inbox panel") }
            }
          }
        }
      }
    }

    let root = Root()
    let tree = FiberTree(root)
    let toolbar = try #require(findNode(tree.renderNode) { $0.attributes["role"] == "toolbar" })
    #expect(toolbar.children.count == 2)
    #expect(toolbar.htmlDescription.contains("Back"))
    #expect(toolbar.htmlDescription.contains("Compose"))

    let inbox = try #require(findNode(tree.renderNode) {
      $0.attributes["role"] == "tab" && $0.attributes["data-tab-label"] == "Inbox"
    })
    tree.dispatch(event: "click", on: inbox)
    _ = tree.update(root)
    #expect(root.selection == 1)
    #expect(tree.renderNode.htmlDescription.contains("Inbox panel"))
  }

  @Test
  func integerSelectionUsesBindingAndRestoresTabFromHistory() throws {
    struct Root: View {
      let selection: Binding<Int>
      let history: TabHistoryRecorder

      var body: some View {
        TabView(selection: selection) {
          Tab("Home", systemImage: "circle", value: 0) { Text("Home panel") }
          Tab("Inbox", systemImage: "circle", value: 1) { Text("Inbox panel") }
        }
        .environment(\.navigationHistory, history)
      }
    }

    var selected = 0
    let selection = Binding<Int>(get: { selected }, set: { selected = $0 })
    let history = TabHistoryRecorder()
    let root = Root(selection: selection, history: history)
    let tree = FiberTree(root)
    let inbox = try #require(findNode(tree.renderNode) {
      $0.attributes["role"] == "tab" && $0.attributes["data-tab-label"] == "Inbox"
    })

    tree.dispatch(event: "click", on: inbox)
    #expect(selected == 1)
    #expect(history.updates.last?.1 == "1")

    let namespace = try #require(history.defaults.keys.first)
    let restore = try #require(history.observers[namespace])
    restore("0")
    #expect(selected == 0)
    #expect(tree.renderNode.htmlDescription.contains("Home panel"))
  }

  @Test
  func unboundTabsKeepInternalSelectionAndRespondToBrowserHistory() throws {
    struct Root: View {
      let history: TabHistoryRecorder
      @State private var selection = "home"

      var body: some View {
        TabView(selection: $selection) {
          Tab("Home", systemImage: "circle", value: "home") { Text("Home panel") }
          Tab("Inbox", systemImage: "circle", value: "inbox") { Text("Inbox panel") }
        }
        .environment(\.navigationHistory, history)
      }
    }

    let history = TabHistoryRecorder()
    let root = Root(history: history)
    let tree = FiberTree(root)
    let inbox = try #require(findNode(tree.renderNode) {
      $0.attributes["role"] == "tab" && $0.attributes["data-tab-label"] == "Inbox"
    })

    tree.dispatch(event: "click", on: inbox)
    #expect(tree.renderNode.htmlDescription.contains("data-selected-tab=\"inbox\""))
    #expect(tree.renderNode.htmlDescription.contains("Inbox panel"))
    #expect(history.updates.last?.1 == "inbox")

    let namespace = try #require(history.defaults.keys.first)
    let restore = try #require(history.observers[namespace])
    restore("home")
    #expect(tree.renderNode.htmlDescription.contains("data-selected-tab=\"home\""))
    #expect(tree.renderNode.htmlDescription.contains("Home panel"))
  }

  @Test
  func presentationDestinationsAndActiveLinksAppearAndDismissWithTheirBindings() throws {
    struct Root: View {
      @State var presented = false
      @State var linkIsActive = false

      var body: some View {
        NavigationStack {
          NavigationLink(
            destination: Text("Linked destination"),
            isActive: $linkIsActive
          ) { Text("Open link") }
          .navigationDestination(isPresented: $presented) { Text("Presented destination") }
        }
      }
    }

    let root = Root()
    let tree = FiberTree(root)
    let link = try #require(tree.findNode(withEvent: "click"))
    tree.dispatch(event: "click", on: link)
    _ = tree.update(root)
    #expect(root.linkIsActive)
    #expect(tree.renderNode.htmlDescription.contains("Linked destination"))

    root.linkIsActive = false
    root.presented = true
    _ = tree.update(root)
    #expect(tree.renderNode.htmlDescription.contains("Presented destination"))
    // The destination is pushed over the root, which is hidden as under a pushed screen.
    var nodes = [tree.renderNode], screens: [_RenderNode] = []
    while let node = nodes.popLast() {
      if node.classes.contains("navigation-root") || node.classes.contains("navigation-destination") { screens.append(node) }
      nodes.append(contentsOf: node.children)
    }
    #expect(screens.first { $0.classes.contains("navigation-root") }?.attributes["aria-hidden"] == "true")
    #expect(screens.first { $0.classes.contains("navigation-presented") }?.attributes["aria-hidden"] == nil)

    struct Item: Identifiable, Hashable {
      let id: Int
      let title: String
    }
    struct SetupRoot: View {
      @State var isPresented = false
      @State var selectedItem: Item?
      var body: some View {
        NavigationStack { Text("Setup root") }
          .navigationTitle(Text("Setup title"))
          .navigationBarTitleDisplayMode(.inline)
          .navigationDestination(isPresented: $isPresented) { Text("Setup presentation") }
          .navigationDestination(item: $selectedItem) { Text($0.title) }
      }
    }

    let setupRoot = SetupRoot()
    let setupTree = FiberTree(setupRoot)
    setupRoot.isPresented = true
    _ = setupTree.update(setupRoot)
    #expect(setupTree.renderNode.htmlDescription.contains("Setup presentation"))
    #expect(setupTree.renderNode.htmlDescription.contains("data-navigation-title=\"Setup title\""))

    setupRoot.isPresented = false
    setupRoot.selectedItem = Item(id: 7, title: "Item destination")
    _ = setupTree.update(setupRoot)
    #expect(setupTree.renderNode.htmlDescription.contains("Item destination"))
  }

  @Test
  func legacyNavigationViewAndTaggedDestinationKeepTheirSwiftUISemantics() {
    struct Root: View {
      @State var selection: String?
      var body: some View {
        NavigationView {
          NavigationLink(
            destination: Text("Tagged destination"),
            tag: "details",
            selection: $selection
          ) {
            Text("Open tagged destination")
          }
        }
      }
    }

    let root = Root()
    let tree = FiberTree(root)
    #expect(tree.renderNode.classes == ["navigation-stack", "navigation-view"])
    let link = tree.findNode(withEvent: "click")
    tree.dispatch(event: "click", on: link)
    _ = tree.update(root)
    #expect(root.selection == "details")
    #expect(tree.renderNode.htmlDescription.contains("Tagged destination"))

    let toolbarItem = StaticHTMLFiberRenderer().render(
      ToolbarItem(placement: .topBarLeading) { Text("Back") }
    )
    #expect(toolbarItem.contains("data-toolbar-placement=\"top-bar-leading\""))
    #expect(toolbarItem.contains("Back"))

    let toolbarGroup = StaticHTMLFiberRenderer().render(
      ToolbarItemGroup(placement: .primaryAction) { Button("Save") {} }
    )
    #expect(toolbarGroup.contains("data-toolbar-group-placement=\"primary-action\""))
    #expect(toolbarGroup.contains("Save"))
  }

  @Test
  func aLabelInAToolbarShowsItsIconAndKeepsItsTitleAsTheAccessibleName() {
    // A navigation bar shows a Label as its icon alone; the title stays the accessible name. A label style the
    // content sets itself still wins over the bar's default.
    let bar = StaticHTMLFiberRenderer().render(
      ToolbarItemGroup(placement: .topBarTrailing) { Label("Contents", systemImage: "list.bullet") }
    )
    #expect(bar.contains("data-label-style=\"icon-only\""))
    #expect(bar.contains("aria-label=\"Contents\""))

    let explicit = StaticHTMLFiberRenderer().render(
      ToolbarItemGroup(placement: .topBarTrailing) { Label("Contents", systemImage: "list.bullet").labelStyle(.titleAndIcon) }
    )
    #expect(!explicit.contains("data-label-style=\"icon-only\""))
  }

  @Test
  func directDestinationLinkPushesAndDismissesThroughNavigationHistory() {
    final class Recorder: NavigationHistoryAdapter {
      var operations: [NavigationHistoryOperation] = []
      func apply(_ operation: NavigationHistoryOperation) { operations.append(operation) }
    }
    struct Destination: View {
      @Environment(\.dismiss) private var dismiss
      var body: some View { Button("Close direct destination") { dismiss() } }
    }
    struct Root: View {
      let history: Recorder
      @State var path = NavigationPath()
      var body: some View {
        NavigationStack(path: $path, history: history) {
          NavigationLink(destination: Destination()) { Text("Open direct destination") }
        }
      }
    }

    let history = Recorder()
    let root = Root(history: history)
    let tree = FiberTree(root)
    let link = tree.findNode(withEvent: "click")
    #expect(link?.attributes["href"] == "/destination")
    tree.dispatch(event: "click", on: link)
    _ = tree.update(root)

    #expect(root.path.count == 1)
    #expect(tree.renderNode.htmlDescription.contains("Close direct destination"))
    #expect(history.operations.count == 1)
    if case .push = history.operations.first {
      // The path is derived from the stable direct-link key.
    } else {
      Issue.record("A direct destination activation should push browser history")
    }

    let destination = tree.renderNode.children.last
    let close = tree.findNode(withEvent: "click", in: destination)
    tree.dispatch(event: "click", on: close)
    _ = tree.update(root)
    #expect(root.path.isEmpty)
    #expect(history.operations.count == 2)
    if case .back = history.operations.last {
      // Dismissing a path destination maps to a browser back operation.
    } else {
      Issue.record("Dismissing a direct destination should move browser history back")
    }
  }

  @Test
  func aPushThePathBindingDeclinesLeavesTheHistoryAlone() {
    final class Recorder: NavigationHistoryAdapter {
      var operations: [NavigationHistoryOperation] = []
      func apply(_ operation: NavigationHistoryOperation) { operations.append(operation) }
    }
    final class Handled { var routes: [Int] = [] }
    struct Root: View {
      let history: Recorder
      let handled: Handled
      var body: some View {
        // The app takes the route elsewhere (another stack, a panel's presenter) and keeps this path empty.
        NavigationStack(path: Binding<[Int]>(get: { [] }, set: { handled.routes.append(contentsOf: $0) })) {
          NavigationLink(value: 7) { Text("Open seven") }
            .navigationDestination(for: Int.self) { Text("Screen \($0)") }
        }
        .environment(\.navigationHistory, history)
      }
    }

    let history = Recorder()
    let handled = Handled()
    let root = Root(history: history, handled: handled)
    let tree = FiberTree(root)
    tree.dispatch(event: "click", on: tree.findNode(withEvent: "click"))
    _ = tree.update(root)

    #expect(handled.routes == [7])
    #expect(!tree.renderNode.htmlDescription.contains("Screen 7"))
    #expect(history.operations.isEmpty)
  }

  @Test
  func aPathSetByCodeIsRecordedInTheHistory() {
    final class Recorder: NavigationHistoryAdapter {
      var operations: [NavigationHistoryOperation] = []
      func apply(_ operation: NavigationHistoryOperation) { operations.append(operation) }
    }
    struct Root: View {
      let history: Recorder
      @State var routes: [Int] = []
      var body: some View {
        VStack {
          Button("Open by code") { routes = [3] }
          Button("Back to the root") { routes = [] }
          NavigationStack(path: $routes) {
            Text("Root")
              .navigationDestination(for: Int.self) { Text("Screen \($0)") }
          }
          .environment(\.navigationHistory, history)
        }
      }
    }

    let history = Recorder()
    let root = Root(history: history)
    let tree = FiberTree(root)
    func button(_ label: String) -> _RenderNode? {
      findNode(tree.renderNode) { $0.events["click"] != nil && $0.htmlDescription.contains(label) }
    }
    tree.dispatch(event: "click", on: button("Open by code"))
    _ = tree.update(root)
    #expect(tree.renderNode.htmlDescription.contains("Screen 3"))
    #expect(history.operations.count == 1)
    if case .push = history.operations.last {} else { Issue.record("A path set by code should push browser history") }

    tree.dispatch(event: "click", on: button("Back to the root"))
    _ = tree.update(root)
    #expect(history.operations.count == 2)
    if case .back = history.operations.last {} else { Issue.record("A path emptied by code should move browser history back") }
  }

  @Test
  func activeDestinationLinkUsesSelectionAndDismissCallbacks() {
    struct Destination: View {
      @Environment(\.dismiss) private var dismiss
      var body: some View { Button("Close active destination") { dismiss() } }
    }
    struct Root: View {
      @State var isActive = false
      var body: some View {
        NavigationStack {
          NavigationLink(destination: Destination(), isActive: $isActive) {
            Text("Open active destination")
          }
        }
      }
    }

    let root = Root()
    let tree = FiberTree(root)
    let link = tree.findNode(withEvent: "click")
    #expect(link?.attributes["href"] == "#navigation")
    tree.dispatch(event: "click", on: link)
    _ = tree.update(root)
    #expect(root.isActive)
    #expect(tree.renderNode.htmlDescription.contains("Close active destination"))

    let presented = tree.renderNode.children.last
    let close = tree.findNode(withEvent: "click", in: presented)
    tree.dispatch(event: "click", on: close)
    _ = tree.update(root)
    #expect(!root.isActive)
    #expect(!tree.renderNode.htmlDescription.contains("Close active destination"))
  }

  @Test
  func unmatchedTypedPathStopsAtTheRootInsteadOfRenderingAnIncorrectDestination() {
    let path = NavigationPath(["unregistered-route"])
    let html = StaticHTMLFiberRenderer().render(
      NavigationStack(path: .constant(path)) { Text("Root only") }
    )
    #expect(html.contains("Root only"))
    #expect(html.contains("data-navigation-depth=\"0\""))
    #expect(!html.contains("navigation-destination"))
  }

  private func findNode(_ node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> _RenderNode? {
    if predicate(node) { return node }
    for child in node.children {
      if let match = findNode(child, where: predicate) { return match }
    }
    return nil
  }

}
