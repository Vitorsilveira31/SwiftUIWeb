import Foundation
import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures

private enum TestAccentKey: EnvironmentKey { static let defaultValue = "black" }
private extension EnvironmentValues {
  var testAccent: String { get { self[TestAccentKey.self] } set { self[TestAccentKey.self] = newValue } }
}

private final class RecordingRuntimeAdapter: FiberRuntimeAdapter {
  var mountedRoot: _RenderNode?
  var mutationBatches: [[Mutation]] = []
  func mount(root: _RenderNode) { mountedRoot = root }
  func apply(_ mutations: [Mutation]) { mutationBatches.append(mutations) }
}

private final class RecordingHistoryAdapter: NavigationHistoryAdapter {
  var operations: [NavigationHistoryOperation] = []
  var latestPath: NavigationPath?
  var callback: ((NavigationPath) -> Void)?

  func apply(_ operation: NavigationHistoryOperation) { operations.append(operation) }
  func update(_ navigationPath: NavigationPath) { latestPath = navigationPath._historySnapshot() }
  func observe(_ callback: @escaping (NavigationPath) -> Void) { self.callback = callback }
}

@Suite
@MainActor
final class FiberRenderingTests {
  @Test
  func testTextEscapingAndModifiers() {
    let view = Text("<hello> & \"world\"")
      .foregroundColor(.red)
      .padding(4)
    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("&lt;hello&gt; &amp; &quot;world&quot;"))
    _expectTrue(html.contains("color: \(Color.red.cssValue);"))
    _expectTrue(html.contains("padding: 4px;"))
  }

  @Test
  func testContainersConditionalsAndForEach() {
    let view = VStack(spacing: 2) {
      Text("Header")
      if true { Text("Shown") }
      ForEach([1, 2, 3], id: \.self) { value in Text("Row \(value)") }
    }
    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("vstack"))
    _expectTrue(html.contains("Header")); _expectTrue(html.contains("Shown"))
    _expectTrue(html.contains("Row 1")); _expectTrue(html.contains("Row 3"))
  }

  @Test
  func testStaticLazyContainersRemainEagerAndDeterministic() {
    let html = StaticHTMLFiberRenderer().render(
      LazyVStack { ForEach(Array(0..<100), id: \.self) { Text("Row \($0)") } }
    )
    _expectTrue(html.contains("Row 0"))
    _expectTrue(html.contains("Row 99"))
  }

  @Test
  func testHashableForEachOverloadAvoidsKeyPathRequirement() {
    let html = StaticHTMLFiberRenderer().render(ForEach(["Fiber", "WASI"]) { Text($0) })
    _expectTrue(html.contains("Fiber")); _expectTrue(html.contains("WASI"))
  }

  @Test
  func testKeyedReconciliationEmitsMoveAndPreservesFibers() {
    let first = ForEach([1, 2, 3], id: \.self) { Text("\($0)") }
    let tree = FiberTree(first)
    let original = tree.root.children.map { ObjectIdentifier($0) }
    let mutations = tree.update(ForEach([3, 1, 2], id: \.self) { Text("\($0)") })
    _expectTrue(mutations.contains { if case .move = $0 { return true }; return false })
    _expectEqual(original[0], ObjectIdentifier(tree.root.children[1]))
    _expectEqual(original[2], ObjectIdentifier(tree.root.children[0]))
  }

  @Test
  func testKeyedStateFollowsIdentityOnReorder() {
    struct Row: View {
      let id: Int
      @State var count = 0
      var body: some View { Button("\(id):\(count)") { count += 1 } }
    }
    let first = ForEach([1, 2], id: \.self) { Row(id: $0) }
    let tree = FiberTree(first)
    _expectNotNil(tree.findNode(withEvent: "click"))
    tree.dispatch(event: "click")
    _ = tree.update(first)
    let reordered = ForEach([2, 1], id: \.self) { Row(id: $0) }
    _ = tree.update(reordered)
    let html = tree.root.renderNode.htmlDescription
    _expectTrue(html.contains("1:1")); _expectTrue(html.contains("2:0"))
    _expectEqual(tree.root.children.count, 2)
  }

  @Test
  func testStateDrivesEventAndRerender() {
    struct Counter: View {
      @State var count = 0
      var body: some View { Button("Increment") { count += 1 } }
    }
    let counter = Counter()
    let tree = FiberTree(counter)
    tree.dispatch(event: "click")
    _ = tree.update(counter)
    _expectTrue(StaticHTMLFiberRenderer().render(counter).contains("Increment"))
    _expectEqual(counter.count, 1)
  }

  @Test
  func testStateMutationInvalidatesExternalFiberHost() {
    struct AsyncStateView: View {
      @State var value = "loading"
      var body: some View { Text(value) }
    }

    let view = AsyncStateView()
    let tree = FiberTree(view)
    var invalidations = 0
    tree.setExternalInvalidationHandler { invalidations += 1 }

    // This mirrors an async URLSession completion: the mutation is not
    // wrapped in a DOM event, so the retained tree must notify its host.
    view.value = "loaded"
    _expectEqual(invalidations, 1)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("loaded"))
  }

  @Test
  func testGenericHTMLElementAndControls() {
    let name = Binding<String>(get: { "Ada" }, set: { _ in })
    let html = StaticHTMLFiberRenderer().render(Form {
      TextField("Name", text: name)
      SecureField("Password", text: name)
      Toggle("Enabled", isOn: Binding(get: { true }, set: { _ in }))
      Divider()
    })
    _expectTrue(html.contains("<form")); _expectTrue(html.contains("type=\"password\""))
    let secureHTML = StaticHTMLFiberRenderer().render(SecureField("Password", text: name))
    _expectFalse(secureHTML.contains("value=\"Ada\""), "SecureField must not serialize credentials into HTML")
    _expectTrue(html.contains("type=\"checkbox\"")); _expectTrue(html.contains("<hr>"))
  }

  @Test
  func testInputEventUpdatesBinding() {
    var value = "before"
    let binding = Binding<String>(get: { value }, set: { value = $0 })
    let tree = FiberTree(TextField("Name", text: binding))
    tree.dispatch(event: "input", value: "after")
    _expectEqual(value, "after")

    let secureTree = FiberTree(SecureField("Password", text: binding))
    secureTree.dispatch(event: "input", value: "secret")
    _expectEqual(value, "secret")
  }

  @Test
  func testRuntimeAdapterReceivesBatchedFiberCommitsAndIdentityEvents() {
    var taps = 0
    let tree = FiberTree(Button("Tap") { taps += 1 })
    let adapter = RecordingRuntimeAdapter()
    tree.mount(to: adapter)
    _expectNotNil(adapter.mountedRoot)

    tree.dispatch(event: "click", at: tree.root.identity)
    _expectEqual(taps, 1)
    _ = tree.update(Text("Done"), to: adapter)
    _expectEqual(adapter.mutationBatches.count, 1)
    _expectFalse(adapter.mutationBatches[0].isEmpty)
  }

  @Test
  func testInsertRemoveReplaceMutations() {
    let tree = FiberTree(Group { Text("A") })
    _expectFalse(tree.update(Group { Text("A"); Text("B") }).isEmpty)
    _expectFalse(tree.update(Group { Text("B") }).isEmpty)
    _expectTrue(tree.update(Button("Replace", action: {})).contains { if case .replace = $0 { return true }; return false })
  }

  @Test
  func testMultipleStateWritesFromOneEventReconcileFinalConditionalBranch() {
    struct MultiWriteView: View {
      @State var showingNewContent = false
      @State var title = "Old"

      var body: some View {
        VStack {
          Button("Update") {
            // Browser actions commonly update selection and navigation state
            // together. Fiber should commit the final snapshot once rather
            // than applying an intermediate branch update to stale DOM.
            showingNewContent = true
            title = "New"
          }
          if showingNewContent {
            Text(title)
          } else {
            Text("Old branch")
          }
        }
      }
    }

    let view = MultiWriteView()
    let tree = FiberTree(view)
    tree.dispatch(event: "click")
    let mutations = tree.update(view)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("New"))
    _expectTrue(mutations.contains { if case .insert = $0 { return true }; return false })
    _expectTrue(mutations.contains { if case .remove = $0 { return true }; return false })
  }

  @Test
  func testMarkupInTextAlwaysEscapes() {
    let html = StaticHTMLFiberRenderer().render(Group { Text("<b>x</b>"); Text("<i>y</i>") })
    _expectTrue(html.contains("&lt;b&gt;x&lt;/b&gt;")); _expectTrue(html.contains("&lt;i&gt;y&lt;/i&gt;"))
    _expectFalse(html.contains("<b>")); _expectFalse(html.contains("<i>"))
  }

  @Test
  func testLifecycleCallbacksFollowFiberBoundaries() {
    var appears = 0; var disappears = 0
    let first = Text("A").onAppear { appears += 1 }.onDisappear { disappears += 1 }
    let tree = FiberTree(first)
    _expectEqual(appears, 1)
    _ = tree.update(first)
    _expectEqual(appears, 1)
    _ = tree.update(Text("B"))
    _expectEqual(disappears, 1)
  }

  @Test
  func testAppConfigurationIsFiberOnly() {
    struct DemoApp: App {
      var body: some View { WindowGroup { Text("App") } }
    }
    if case .fiber = DemoApp._configuration.reconciler { _expectTrue(true) }
    else { _fail("App configuration must use Fiber") }
    _expectTrue(StaticHTMLFiberRenderer().render(DemoApp()).contains("App"))
  }

  @Test
  func testEnvironmentModifierIsVisibleDuringFiberEvaluation() {
    struct Reader: View {
      @Environment(\.testAccent) var accent
      var body: some View { Text(accent) }
    }
    let html = StaticHTMLFiberRenderer().render(Reader()._environment(TestAccentKey.self, "violet"))
    _expectTrue(html.contains("violet"))
  }

  @Test
  func testSwiftUIStyleCompatibilityFixtureCompilesThroughFiber() {
    struct Item: Hashable { let id: Int; let title: String }
    struct CompatibilityView: View {
      let items: [Item]
      @State var selected = 0
      @State var presented = false
      @State var path = NavigationPath()

      var body: some View {
        NavigationStack(path: $path) {
          VStack {
            Text("Selected \(selected)")
            ForEach(items, id: \.id) { item in
              NavigationLink(value: item) { Text(item.title) }
            }
            Button("Settings") { presented = true }
          }
          .sheet(isPresented: $presented) { Text("Settings") }
          .alert("Notice", isPresented: $presented) { Button("OK") {} }
          .toolbar { Text("Toolbar") }
          .navigationDestination(for: Item.self) { item in Text(item.title) }
        }
      }
    }

    let html = StaticHTMLFiberRenderer().render(CompatibilityView(items: [Item(id: 1, title: "One")]))
    _expectTrue(html.contains("navigation-stack"))
    _expectTrue(html.contains("One"))
  }

  @Test
  func testBindingPropertyWrapperAndThemeEnvironment() {
    struct Child: View {
      @Binding var value: Int
      @Environment(\.colorScheme) var scheme
      var body: some View {
        Button("\(scheme.rawValue):\(value)") { value += 1 }
      }
    }

    var value = 3
    let binding = Binding(get: { value }, set: { value = $0 })
    let tree = FiberTree(Child(value: binding).preferredColorScheme(.dark))
    _expectTrue(tree.renderNode.htmlDescription.contains("dark:3"))
    tree.dispatch(event: "click")
    _expectEqual(value, 4)
  }

  @Test
  func testPresentationTabsOverlaysAndResponsiveMetadata() {
    struct PresentationFixture: View {
      @State var presented = true
      var body: some View {
        TabView(selection: Binding.constant(1)) {
          Text("Selected")
        }
        .background(.gray)
        .overlay { Text("Overlay") }
        .sheet(isPresented: $presented) { Text("Sheet") }
        .alert("Notice", isPresented: $presented, actions: { Button("OK") {} }, message: { Text("Message") })
      }
    }

    let html = StaticHTMLFiberRenderer().render(PresentationFixture())
    _expectTrue(html.contains("tab-view"))
    _expectTrue(html.contains("data-selected-tab=\"1\""))
    _expectTrue(html.contains("overlay-layer"))
    _expectTrue(html.contains("data-presentation=\"sheet\""))
    _expectTrue(html.contains("data-presentation=\"alert\""))

    let modal = StaticHTMLFiberRenderer().render(Text("Base").fullScreenCover(isPresented: Binding.constant(true)) { Text("Modal") })
    _expectTrue(Binding.constant(true).wrappedValue)
    _expectTrue(modal.contains("data-presentation=\"full-screen-cover\""))

    let responsive = StaticHTMLFiberRenderer().render(ResponsiveView { Text("Compact") } regular: { Text("Regular") })
    _expectTrue(responsive.contains("responsive-compact"))
    _expectTrue(responsive.contains("responsive-regular"))
  }

  @Test
  func testPresentationSurfacesExposeStableDesignSystemRegions() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Base")
        .sheet(isPresented: Binding.constant(true)) {
          Text("Sheet body")
        }
        .alert(
          "Delete item?",
          isPresented: Binding.constant(true),
          actions: { Button("Delete", role: .destructive) {} },
          message: { Text("This cannot be undone.") }
        )
    )
    _expectTrue(html.contains("presentation-header"))
    _expectTrue(html.contains("presentation-content"))
    _expectTrue(html.contains("presentation-message"))
    _expectTrue(html.contains("presentation-actions"))
    _expectTrue(html.contains("sheet-content"))
    _expectTrue(html.contains("alert-actions"))
  }

  @Test
  func testNavigationPathTypedDestinationPushPopAndDismiss() {
    enum Route: Hashable { case detail(Int) }
    final class Recorder { var dismissCount = 0 }
    let recorder = Recorder()

    struct Detail: View {
      let id: Int
      let recorder: Recorder
      @Environment(\.dismiss) private var dismiss
      var body: some View {
        Button("Dismiss \(id)") { dismiss(); recorder.dismissCount += 1 }
          .navigationTitle("Detail")
      }
    }

    struct Root: View {
      @State var path = NavigationPath()
      let recorder: Recorder
      var body: some View {
        NavigationStack(path: $path) {
          VStack {
            NavigationLink("Open detail", value: Route.detail(7))
            Button("Replace route") { path.replaceLast(Route.detail(8)) }
          }
          .navigationTitle("Home")
          .navigationBarTitleDisplayMode(.inline)
          .navigationDestination(for: Route.self) { route in
            switch route {
            case .detail(let id): Detail(id: id, recorder: recorder)
            }
          }
        }
      }
    }

    let root = Root(recorder: recorder)
    let tree = FiberTree(root)
    _expectEqual(root.path.count, 0)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-navigation-title=\"Home\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("data-navigation-link=\"push\""))

    tree.dispatch(event: "click")
    _ = tree.update(root)
    _expectEqual(root.path.count, 1)
    _expectTrue(tree.renderNode.htmlDescription.contains("Dismiss 7"))
    _expectTrue(tree.renderNode.htmlDescription.contains("data-navigation-depth=\"1\""))

    let dismissNode = tree.findNode(withEvent: "click", in: tree.renderNode.children.last)
    _expectNotNil(dismissNode)
    tree.dispatch(event: "click", on: dismissNode)
    _expectEqual(recorder.dismissCount, 1)
    _ = tree.update(root)
    _expectEqual(root.path.count, 0)
    _expectFalse(tree.renderNode.htmlDescription.contains("Dismiss 7"))

    var path = NavigationPath([Route.detail(1)])
    path.replaceLast(Route.detail(2))
    _expectEqual(path.count, 1)
    path.removeLast()
    _expectTrue(path.isEmpty)
  }

  @Test
  func testNavigationStackKeepsInactiveFibersMountedButHidesThem() {
    enum Route: Hashable { case category, detail }

    struct Root: View {
      @State var path = NavigationPath([Route.category, Route.detail])
      var body: some View {
        NavigationStack(path: $path) {
          Text("Root")
            .navigationDestination(for: Route.self) { route in
              switch route {
              case .category: Text("Category")
              case .detail: Text("Detail")
              }
            }
        }
      }
    }

    let html = FiberTree(Root()).renderNode.htmlDescription
    _expectTrue(html.contains("data-navigation-inactive=\"true\""))
    _expectTrue(html.contains("aria-hidden=\"true\""))
    _expectTrue(html.contains("Detail"))
  }

  @Test
  func testNavigationHistoryRestorationKeepsTheNextPushObservable() {
    enum Route: Hashable { case category }

    struct Root: View {
      @State var path = NavigationPath()
      let history: RecordingHistoryAdapter

      var body: some View {
        NavigationStack(path: $path, history: history) {
          Button("Push") { path.append(Route.category) }
            .navigationDestination(for: Route.self) { _ in Text("Category") }
        }
      }
    }

    let history = RecordingHistoryAdapter()
    let root = Root(history: history)
    let tree = FiberTree(root)

    tree.dispatch(event: "click")
    _expectEqual(history.operations.count, 1)
    _expectEqual(root.path.count, 1)

    // Simulate a browser Back entry restoring the root, then update Fiber as
    // the browser host does. The observer baseline must move with that entry
    // so the next declarative push emits a new history operation.
    history.callback?(NavigationPath())
    _ = tree.update(root)
    _expectTrue(root.path.isEmpty)

    tree.dispatch(event: "click")
    _expectEqual(history.operations.count, 2)
    _expectEqual(root.path.count, 1)
  }

  @Test
  func testNavigationDestinationIsPresentedAndItemDismiss() {
    struct Item: Identifiable, Hashable {
      let id: Int
    }

    struct Root: View {
      @State var isPresented = true
      @State var item: Item? = Item(id: 42)
      var body: some View {
        NavigationStack {
          Text("Root")
            .navigationDestination(isPresented: $isPresented) { Text("Presented") }
            .navigationDestination(item: $item) { value in Text("Item \(value.id)") }
        }
      }
    }

    let root = Root()
    let tree = FiberTree(root)
    let html = tree.renderNode.htmlDescription
    _expectTrue(html.contains("Presented") || html.contains("Item 42"))
    root.isPresented = false
    root.item = nil
    _ = tree.update(root)
    _expectFalse(tree.renderNode.htmlDescription.contains("Presented"))
    _expectFalse(tree.renderNode.htmlDescription.contains("Item 42"))
  }

  @Test
  func testDismissEnvironmentActionCanBeInjected() {
    var called = false
    var environment = EnvironmentValues()
    environment.dismiss = DismissAction { called = true }
    environment.dismiss()
    _expectTrue(called)
    called = false
    struct DismissReader: View {
      @Environment(\.dismiss) var dismiss
      var body: some View { Button("Dismiss") { dismiss() } }
    }
    let view = DismissReader().environment(\.dismiss, DismissAction { called = true })
    let tree = FiberTree(view)
    tree.dispatch(event: "click")
    _expectTrue(called)
  }

  @Test
  func testSwiftUIShapedPresentationOverloadsCompileAndRender() {
    struct Item: Identifiable, Hashable {
      let id: Int
    }

    struct Fixture: View {
      @State var path = NavigationPath()
      @State var item: Item? = Item(id: 7)
      @State var cover: Item? = Item(id: 8)
      @State var popover: Item? = Item(id: 9)
      @State var alertPresented = true
      @State var confirmationPresented = true

      var body: some View {
        NavigationStack(path: $path) {
          Text("Root")
            .sheet(item: $item, onDismiss: {}) { value in Text("Sheet \(value.id)") }
            .fullScreenCover(item: $cover, onDismiss: {}) { value in Text("Cover \(value.id)") }
            .popover(item: $popover) { value in Text("Popover \(value.id)") }
            .alert("Delete item?", isPresented: $alertPresented, actions: {
              Button("Delete", role: .destructive) {}
              Button("Cancel", role: .cancel) {}
            }, message: { Text("This cannot be undone.") })
            .confirmationDialog("Choose an action", isPresented: $confirmationPresented, actions: {
              Button("Edit") {}
              Button("Cancel", role: .cancel) {}
            }, message: { Text("Select one.") })
        }
      }
    }

    let html = StaticHTMLFiberRenderer().render(Fixture())
    _expectTrue(html.contains("data-presentation=\"sheet\""))
    _expectTrue(html.contains("data-presentation=\"full-screen-cover\""))
    _expectTrue(html.contains("data-presentation=\"popover\""))
    _expectTrue(html.contains("data-presentation=\"alert\""))
    _expectTrue(html.contains("data-presentation=\"confirmation-dialog\""))
  }

  @Test
  func testPresentationDismissEnvironmentUpdatesItsBinding() {
    struct SheetContent: View {
      @Environment(\.dismiss) var dismiss
      var body: some View { Button("Close") { dismiss() } }
    }
    struct Root: View {
      @State var presented = true
      var body: some View { Text("Root").sheet(isPresented: $presented) { SheetContent() } }
    }

    let root = Root()
    let tree = FiberTree(root)
    _expectTrue(tree.renderNode.htmlDescription.contains("Close"))
    tree.dispatch(event: "click")
    _expectFalse(root.presented)
    _ = tree.update(root)
    _expectFalse(tree.renderNode.htmlDescription.contains("Close"))
  }

  @Test
  func testPresentationBackdropDismissUsesContextualDismissAction() {
    struct Root: View {
      @State var presented = true
      var body: some View {
        Text("Root").sheet(isPresented: $presented) {
          Text("Sheet").interactiveDismissDisabled(false)
        }
      }
    }

    let root = Root()
    let tree = FiberTree(root)
    let presentation = tree.findNode(withEvent: "presentation-dismiss")
    _expectNotNil(presentation)
    tree.dispatch(event: "presentation-dismiss", on: presentation)
    _expectFalse(root.presented)
  }

  @Test
  func testInteractiveDismissDisabledMarkerRemainsInsidePresentationContent() {
    struct Root: View {
      @State var presented = true
      var body: some View {
        Text("Root").sheet(isPresented: $presented) {
          Text("Sheet").interactiveDismissDisabled()
        }
      }
    }

    let html = StaticHTMLFiberRenderer().render(Root())
    _expectTrue(html.contains("data-interactive-dismiss-disabled=\"true\""))
  }

  @Test
  func testNavigationHistoryAdapterReceivesDeclarativeOperations() {
    final class Recorder: NavigationHistoryAdapter {
      var operations: [NavigationHistoryOperation] = []
      func apply(_ operation: NavigationHistoryOperation) { operations.append(operation) }
      func path(for navigationPath: NavigationPath) -> String {
        navigationPath.isEmpty ? "/" : "/catalog/\(navigationPath.count)"
      }
    }
    enum Route: Hashable { case details, settings }

    struct Destination: View {
      @Environment(\.dismiss) var dismiss
      var body: some View { Button("Dismiss") { dismiss() } }
    }

    struct Root: View {
      @State var path = NavigationPath()
      let recorder: Recorder
      var body: some View {
        NavigationStack(path: $path, history: recorder) {
          VStack {
            NavigationLink("Details", value: Route.details)
          }
          .navigationDestination(for: Route.self) { _ in
            Destination()
          }
        }
      }
    }

    let recorder = Recorder()
    let root = Root(recorder: recorder)
    let tree = FiberTree(root)
    _expectTrue(tree.renderNode.htmlDescription.contains("href=\"/catalog/1\""))
    tree.dispatch(event: "click")
    _ = tree.update(root)
    _expectEqual(recorder.operations, [.push(path: "/catalog/1")])

    let dismiss = tree.findNode(withEvent: "click", in: tree.renderNode.children.last)
    _expectNotNil(dismiss)
    tree.dispatch(event: "click", on: dismiss)
    _ = tree.update(root)
    _expectEqual(recorder.operations.last, .back(path: "/"))

    root.path.append(Route.details)
    _expectEqual(recorder.operations.last, .push(path: "/catalog/1"))
    root.path.replaceLast(Route.settings)
    _expectEqual(recorder.operations.last, .replace(path: "/catalog/1"))
    root.path.removeAll()
    _expectEqual(recorder.operations.last, .back(path: "/"))
  }

  @Test
  func testNavigationModifiersAttachedOutsideStackAreAdopted() {
    enum Route: Hashable { case settings }
    struct Root: View {
      @State var path = NavigationPath()
      var body: some View {
        NavigationStack(path: $path) {
          NavigationLink("Settings", value: Route.settings)
        }
        .navigationTitle("Outer title")
        .navigationDestination(for: Route.self) { _ in Text("Settings") }
      }
    }

    let root = Root()
    let tree = FiberTree(root)
    _expectTrue(tree.renderNode.htmlDescription.contains("Outer title"))
    tree.dispatch(event: "click")
    _ = tree.update(root)
    _expectTrue(tree.renderNode.htmlDescription.contains("Settings"))
  }
}
