import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
import SwiftUIWebWeb
@_spi(Browser) @_spi(WebMount) @_spi(Renderer) @testable import SwiftUIWebBrowser

/// Native behaviour of the browser adapter's host-neutral pieces: DOMView
/// snapshot staging, WebMount registration lifetime, prefetch planning, feature
/// loading and the BrowserApp entry point.
@Suite(.processGlobalState)
@MainActor
final class BrowserRuntimeAdapterTests {
  private final class FirstKind {}
  private final class SecondKind {}

  private func descriptor(_ identity: Any.Type, component: String = "stage") -> _DOMViewDescriptor {
    _DOMViewDescriptor(
      identity: identity,
      make: { _DOMViewInstance(coordinator: 0, domView: DOMView(component: component)) },
      update: { _ in },
      receive: { _, _ in },
      dismantle: { _ in }
    )
  }

  // MARK: - DOMView runtime

  @Test
  func domViewSnapshotsKeepOnlyTheTokensStagedInTheLatestPass() {
    _DOMViewRuntime.install()
    _DOMViewRuntime.install()  // idempotent: one registry entry per process

    let first = descriptor(FirstKind.self)
    let second = descriptor(SecondKind.self)
    _DOMViewRuntime.beginSnapshot()
    _DOMViewRuntime.stage(token: "view-a", descriptor: first)
    _DOMViewRuntime.stage(token: "view-b", descriptor: second)
    _DOMViewRuntime.finishSnapshot()
    #expect(_DOMViewRuntime.descriptor(for: "view-a") === first)
    #expect(_DOMViewRuntime.descriptor(for: "view-b") === second)

    // A later pass that no longer renders view-a drops its descriptor, and a
    // re-staged token picks up the newest descriptor.
    let replacement = descriptor(SecondKind.self, component: "replacement")
    _DOMViewRuntime.beginSnapshot()
    _DOMViewRuntime.stage(token: "view-b", descriptor: replacement)
    _DOMViewRuntime.finishSnapshot()
    #expect(_DOMViewRuntime.descriptor(for: "view-a") == nil)
    #expect(_DOMViewRuntime.descriptor(for: "view-b") === replacement)

    _DOMViewRuntime.beginSnapshot()
    _DOMViewRuntime.finishSnapshot()
    #expect(_DOMViewRuntime.descriptor(for: "view-b") == nil)
  }

  // MARK: - WebMount

  private final class RecordingController: WebMountController {
    func mount(element: WebElementHandle, token: String) {}
    func update(element: WebElementHandle, token: String) {}
    func unmount() {}
  }

  @Test
  func webMountRegistrationsAreReplaceableAndCancelIdempotently() {
    let registry = WebMountRegistry.shared
    let first = registry.register(key: "runtime-adapter-test") { _, _ in RecordingController() }
    let replacement = registry.register(key: "runtime-adapter-test") { _, _ in RecordingController() }
    // Cancelling the first token removes the key; the replacement's token is
    // then a no-op instead of failing, and cancelling twice is harmless.
    first.cancel()
    replacement.cancel()
    replacement.cancel()
    // Native hosts have no live DOM mounts to dispose.
    registry.dispose(token: "missing-token")

    // `dispose` is optional for controllers.
    RecordingController().dispose()

    var cancelled = 0
    do {
      let subscription = WebSubscription { cancelled += 1 }
      _ = subscription
    }
    #expect(cancelled == 1, "releasing a subscription cancels it")
  }

  @Test
  func webMountSurfaceRendersItsSemanticKey() {
    let surface = WebMountSurface(tag: "section", key: "map")
    let node = surface._render(in: _RenderContext())
    #expect(node.kind.displayName == "section")
    #expect(node.attributes["data-web-mount-key"] == "map")
    #expect(WebMountSurface(key: "chart").tag == "div")
    #expect(WebMediaTimeRange(start: 1, end: 2) == WebMediaTimeRange(start: 1, end: 2))
  }

  // MARK: - Prefetch planner

  @Test
  func plannerPolicyUpdatesGateEveryBatch() {
    let planner = _WebPrefetchPlanner()
    let idle = _WebPrefetchResource(url: "/idle.js", kind: .module)
    planner.register(idle)
    #expect(planner.hasPendingIdleResources)
    planner.update(policy: _WebPrefetchPolicy(enabled: false))
    #expect(planner.policy.enabled == false)
    #expect(planner.idleBatch().isEmpty)
    planner.update(policy: _WebPrefetchPolicy())
    #expect(planner.idleBatch(limit: 0).isEmpty)
    #expect(planner.idleBatch() == [idle])

    planner.markDispatched(idle)
    #expect(!planner.hasPendingIdleResources)
    // Replacing the document clears dispatch history but keeps registrations.
    planner.resetDispatchHistory()
    #expect(planner.hasPendingIdleResources)
    #expect(planner.idleBatch() == [idle])
  }

  @Test
  func plannerOrdersEqualPrioritiesByRegistrationAndCountsTheBudget() {
    let planner = _WebPrefetchPlanner(policy: _WebPrefetchPolicy(maxViewportResourcesPerDrain: 2))
    let resources = (0..<3).map {
      _WebPrefetchResource(url: "/tile-\($0).png", kind: .image, trigger: .viewport(nil), priority: 50)
    }
    planner.register(resources)
    let route = _WebPrefetchResource(url: "/route.js", kind: .module, trigger: .route("/a"))
    planner.register(route)
    #expect(!planner.hasPendingIdleResources, "route and viewport entries never wait for idle time")
    // An unscoped viewport resource matches any scope.
    #expect(planner.viewportBatch(scope: "map").map(\.url) == ["/tile-0.png", "/tile-1.png"])
    #expect(planner.metrics.skippedBudget == 1)
    #expect(planner.viewportBatch(scope: nil, limit: 5).count == 3)
  }

  @Test
  func plannerPrunesDispatchedEntriesPastItsCapacity() {
    let planner = _WebPrefetchPlanner(policy: _WebPrefetchPolicy(maxTotalResources: 4))
    // The retained manifest is capped at max(64, 4 * maxTotalResources).
    let early = (0..<64).map { _WebPrefetchResource(url: "/early-\($0).png", kind: .image, trigger: .viewport("feed")) }
    planner.register(early)
    early.forEach(planner.markDispatched)
    let late = (0..<4).map { _WebPrefetchResource(url: "/late-\($0).png", kind: .image, trigger: .viewport("feed")) }
    planner.register(late)
    // Pruned entries keep their dispatch record, so they are never re-hinted;
    // the new resources remain pending.
    #expect(planner.viewportBatch(scope: "feed", limit: 100).map(\.url).sorted() == late.map(\.url).sorted())
    #expect(early.allSatisfy(planner.isDispatched))
    #expect(planner.metrics.registrations == 68)
  }

  @Test
  func runtimeRegistrationsAdvanceTheGenerationOnlyWhenTheManifestChanges() {
    let start = WebPrefetchRuntime._registrationGeneration
    let viewport = _WebPrefetchResource(url: "/runtime-adapter-viewport.js", kind: .script, trigger: .viewport(nil))
    let token = WebPrefetchRuntime.register(viewport)
    #expect(WebPrefetchRuntime._registrationGeneration == start &+ 1)
    #expect(WebPrefetchRuntime._registeredResources().contains(viewport))
    token.cancel()
    #expect(WebPrefetchRuntime._registrationGeneration == start &+ 2)
    token.cancel()
    #expect(WebPrefetchRuntime._registrationGeneration == start &+ 2)
    #expect(!WebPrefetchRuntime._registeredResources().contains(viewport))
  }

  // MARK: - Feature loading

  @Test
  func featureManifestsRegisterTogetherAndLoadOnlyInABrowser() async {
    let manifests = [
      _WebFeatureManifest(id: "runtime-chart", entry: "/features/runtime-chart.js", styles: ["/features/runtime-chart.css"]),
      _WebFeatureManifest(id: "runtime-map", entry: "/features/runtime-map.js", viewportScope: "map"),
      _WebFeatureManifest(id: "", entry: "/features/ignored.js"),
    ]
    #expect(manifests[2]._prefetchResources.isEmpty, "a manifest without an id contributes nothing")
    let idle = manifests[0]._prefetchResources
    #expect(idle.map(\.priority) == [80, 82])
    let registration = WebFeatureRuntime.register(manifests)
    let registered = WebPrefetchRuntime._registeredResources()
    #expect((idle + manifests[1]._prefetchResources).allSatisfy(registered.contains))
    registration.cancel()
    #expect(!WebPrefetchRuntime._registeredResources().contains(idle[0]))

    WebFeatureRuntime.prefetch(manifests[0])
    WebFeatureRuntime.prefetchRoute("/map")
    for load in [
      { _ = try await WebFeatureRuntime.load(manifests[0]) },
      { _ = try await WebFeatureRuntime.loadFromManifest(id: "runtime-map") },
    ] as [@MainActor () async throws -> Void] {
      do {
        try await load()
        Issue.record("feature loading must require a browser host")
      } catch let error as _WebFeatureLoadError {
        #expect(error == _WebFeatureLoadError("Web feature loading requires a browser WebAssembly host"))
      } catch {
        Issue.record("unexpected error: \(error)")
      }
    }
  }

  // MARK: - App entry point

  private struct TitledApp: BrowserApp {
    var body: some View { Text("Hello") }
  }

  @Test
  func browserAppLaunchesThroughFiberAndPublishesItsTitle() {
    let previous = AppTitleRuntime.current
    defer { if let previous { AppTitleRuntime.set(previous) } else { AppTitleRuntime.current = nil } }
    TitledApp._launch(TitledApp(), with: _AppConfiguration())
    TitledApp._setTitle("Inbox")
    #expect(AppTitleRuntime.current == "Inbox")
  }

  // MARK: - Native backends and buffers

  @Test
  func nativeAnimationBackendsAreInert() {
    let animations = BrowserAdvancedAnimationBackend()
    animations.synchronize(document: 0)
    animations.dispose()
    let mesh = BrowserMeshGradientBackend()
    mesh.synchronize(document: 0)
    mesh.dispose()
    var refreshed = false
    let dragDrop = BrowserDragDropController()
    dragDrop.synchronize(document: 0, resolveNode: { _ in nil }, requestRefresh: { refreshed = true })
    dragDrop.releaseAll()
    #expect(!refreshed)
    #expect(_BrowserLayoutPhaseCoordinator.shared === _BrowserLayoutPhaseCoordinator.shared)
  }

  @Test
  func byteBufferStoresBytesAndReleasesItsStorage() {
    var buffer = _EmbeddedByteBuffer()
    #expect(buffer.address == 0)
    buffer.store([1, 2, 3])
    #expect(buffer.count == 3)
    #expect(buffer.address != 0)
    let pointer = buffer.pointer!
    #expect((0..<3).map { pointer[$0] } == [1, 2, 3])
    buffer.store([])
    #expect(buffer.count == 0)
    // Commits are clamped to the reserved capacity.
    _ = buffer.reserve(4)
    buffer.commit(buffer.capacity + 10)
    #expect(buffer.count == buffer.capacity)
    buffer.commit(-1)
    #expect(buffer.count == 0)
    buffer.store(Array(repeating: 9, count: 8))
    buffer.release()
    #expect(buffer.pointer == nil)
    #expect(buffer.capacity == 0)
    #expect(buffer.address == 0)
  }
}
