import Testing
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// SwiftUI resolves `@Environment` when a view is updated. The value stays
/// attached to that view value, so `.task` bodies, `Task {}` started by an
/// action and async helpers keep reading it after the render pass (and after
/// any suspension point) has finished.
@Suite
@MainActor
struct EnvironmentAsyncResolutionTests {
  final class CatalogStore: @unchecked Sendable {
    var skills: [String] = []
    var loads = 0
    func load() async {
      await Task.yield()
      loads += 1
      skills = ["plot", "dialogue"]
    }
  }

  final class Probe: @unchecked Sendable {
    var values: [String] = []
    var finished = false
  }

  fileprivate enum ProbeLabelKey: EnvironmentKey { static let defaultValue = "default" }

  /// Mirrors a catalog screen whose `.task` calls an async method that reads
  /// the injected store only after suspending.
  private struct CatalogView: View {
    @Environment(CatalogStore.self) private var store
    let probe: Probe

    var body: some View {
      Text("Catalog").task { await loadCatalog() }
    }

    private func loadCatalog() async {
      await Task.yield()
      if store.skills.isEmpty { await store.load() }
      probe.values = store.skills
      probe.finished = true
    }
  }

  fileprivate struct SaveButton: View, @unchecked Sendable {
    @Environment(\.probeLabel) fileprivate var label
    @Environment(CatalogStore.self) private var store
    let probe: Probe

    var body: some View {
      Button("Save") {
        Task {
          await Task.yield()
          probe.values.append(label)
          probe.values.append(String(store.loads))
          probe.finished = true
        }
      }
    }
  }

  @Test
  func taskReadsInjectedModelAfterSuspending() async {
    let store = CatalogStore()
    let probe = Probe()
    let tree = FiberTree(
      VStack { CatalogView(probe: probe) }.environment(store),
      deferLazyCollections: false,
      startLifecycle: false
    )
    defer { tree._dispose() }
    tree._startLifecycle()
    await waitUntil { probe.finished }

    #expect(probe.values == ["plot", "dialogue"])
    #expect(store.loads == 1)
  }

  @Test
  func taskStartedByAnActionKeepsTheViewEnvironment() async {
    let store = CatalogStore()
    store.loads = 7
    let probe = Probe()
    let tree = FiberTree(
      VStack { SaveButton(probe: probe).environment(\.probeLabel, "sheet") }.environment(store),
      deferLazyCollections: false,
      startLifecycle: false
    )
    defer { tree._dispose() }
    tree._startLifecycle()
    guard let button = firstButton(in: tree.root) else {
      Issue.record("Save button was not rendered")
      return
    }
    tree.dispatch(event: "click", at: button.identity)
    await waitUntil { probe.finished }

    #expect(probe.values == ["sheet", "7"])
  }

  @Test
  func copiesOfARenderedViewShareTheResolvedEnvironment() {
    let store = CatalogStore()
    store.loads = 3
    var captured: SaveButton?
    let probe = Probe()
    struct Capture: View {
      let make: () -> SaveButton
      let capture: (SaveButton) -> Void
      var body: some View {
        let button = make()
        capture(button)
        return button
      }
    }
    let tree = FiberTree(
      Capture(make: { SaveButton(probe: probe) }, capture: { captured = $0 })
        .environment(\.probeLabel, "outer")
        .environment(store),
      deferLazyCollections: false,
      startLifecycle: false
    )
    defer { tree._dispose() }
    _ = tree.renderNode

    // Outside of any render pass and any event: the copy still resolves.
    #expect(EnvironmentRuntime.installed == nil)
    #expect(captured?.resolvedLabel == "outer")
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() {
      await Task.yield()
    }
  }

  private func firstButton(in fiber: Fiber) -> Fiber? {
    if fiber.renderNode.attributes["data-control-kind"] == "button" { return fiber }
    for child in fiber.children {
      if let match = firstButton(in: child) { return match }
    }
    return nil
  }
}

private extension EnvironmentAsyncResolutionTests.SaveButton {
  var resolvedLabel: String { label }
}

private extension EnvironmentValues {
  var probeLabel: String {
    get { self[EnvironmentAsyncResolutionTests.ProbeLabelKey.self] }
    set { self[EnvironmentAsyncResolutionTests.ProbeLabelKey.self] = newValue }
  }
}
