import Foundation
import Testing
@_spi(Browser) import SwiftUIWebBrowser

@Suite(.processGlobalState)
@MainActor
final class BrowserPrefetchTests {
  @Test
  func testPlannerDeduplicatesAndPrioritizesIdleResources() {
    let planner = _WebPrefetchPlanner(policy: _WebPrefetchPolicy(maxIdleResourcesPerDrain: 2))
    let low = _WebPrefetchResource(url: "/feature/low.js", kind: .module, priority: 80)
    let high = _WebPrefetchResource(url: "/feature/high.js", kind: .module, priority: 5)
    planner.register(low)
    planner.register(low)
    planner.register(high)

    let batch = planner.idleBatch()
    _expectEqual(batch.map(\.url), ["/feature/high.js", "/feature/low.js"])
    _expectEqual(planner.metrics.registrations, 3)
    _expectEqual(planner.metrics.deduplicatedRegistrations, 1)

    planner.markDispatched(high)
    _expectFalse(planner.idleBatch().contains(high))
    _expectTrue(planner.hasPendingResources)
  }

  @Test
  func testRouteAndViewportTriggersStayOutOfIdleQueue() {
    let planner = _WebPrefetchPlanner()
    let route = _WebPrefetchResource(
      url: "/settings.js",
      kind: .module,
      trigger: .route("/settings/"),
      priority: 1
    )
    let map = _WebPrefetchResource(
      url: "https://cdn.example.test/map.js",
      kind: .script,
      trigger: .viewport("map"),
      priority: 2,
      allowCrossOrigin: true
    )
    planner.register([route, map])

    _expectTrue(planner.idleBatch().isEmpty)
    _expectEqual(planner.intentBatch(route: "/settings#top").map(\.url), ["/settings.js"])
    _expectEqual(planner.viewportBatch(scope: "map").map(\.url), ["https://cdn.example.test/map.js"])
    _expectTrue(planner.viewportBatch(scope: "chart").isEmpty)
  }

  @Test
  func testPolicyBoundsAndDispatchKeyAreStableAcrossTriggers() {
    let policy = _WebPrefetchPolicy(
      maxIdleResourcesPerDrain: 1,
      maxIntentResourcesPerDrain: 1,
      maxViewportResourcesPerDrain: 1,
      maxTotalResources: 3
    )
    let planner = _WebPrefetchPlanner(policy: policy)
    let resource = _WebPrefetchResource(url: "/shared.js", kind: .module, trigger: .idle)
    let sameURLForRoute = _WebPrefetchResource(url: "/shared.js", kind: .module, trigger: .route("/next"))
    planner.register([resource, sameURLForRoute])

    _expectEqual(planner.idleBatch().count, 1)
    planner.markDispatched(resource)
    _expectTrue(planner.isDispatched(sameURLForRoute))
    _expectFalse(planner.hasPendingResources)

    let clamped = _WebPrefetchPolicy(maxIdleResourcesPerDrain: -1, maxTotalResources: -4)
    _expectEqual(clamped.maxIdleResourcesPerDrain, 0)
    _expectEqual(clamped.maxTotalResources, 0)
  }

  @Test
  func testWrapperRegistrationHasExplicitCleanup() {
    let resource = _WebPrefetchResource(
      url: "/unique-prefetch-registration-test.js",
      kind: .module,
      trigger: .route("/test")
    )
    let token = WebPrefetchRuntime.register(resource)
    _expectTrue(WebPrefetchRuntime._registeredResources().contains(resource))
    token.cancel()
    _expectFalse(WebPrefetchRuntime._registeredResources().contains(resource))
  }

  @Test
  func testStaleRegistrationCannotCancelReplacement() {
    let first = _WebPrefetchResource(url: "/replacement.js", kind: .module, priority: 20)
    let replacement = _WebPrefetchResource(url: "/replacement.js", kind: .module, priority: 5)
    let firstToken = WebPrefetchRuntime.register(first)
    let replacementToken = WebPrefetchRuntime.register(replacement)
    firstToken.cancel()
    _expectTrue(WebPrefetchRuntime._registeredResources().contains(replacement))
    replacementToken.cancel()
    _expectFalse(WebPrefetchRuntime._registeredResources().contains(replacement))
  }

  @Test
  func testFeatureManifestProducesRouteScopedSidecarResources() {
    let manifest = _WebFeatureManifest(
      id: "map-fixture",
      entry: "/features/map.js",
      styles: ["/features/map.css"],
      workers: ["/features/map.worker.js"],
      routes: ["/map"]
    )
    let resources = manifest._prefetchResources
    _expectEqual(resources.count, 3)
    _expectTrue(resources.allSatisfy {
      if case .route("/map") = $0.trigger { return true }
      return false
    })
    _expectEqual(resources.map(\.kind), [.module, .stylesheet, .worker])

    let registration = WebFeatureRuntime.register(manifest)
    _expectTrue(resources.allSatisfy { WebPrefetchRuntime._registeredResources().contains($0) })
    registration.cancel()
    _expectTrue(resources.allSatisfy { !WebPrefetchRuntime._registeredResources().contains($0) })
  }

  @Test
  func testFeatureManifestUsesViewportOrIdleFallbackWithoutRoutes() {
    let viewport = _WebFeatureManifest(
      id: "chart-fixture",
      entry: "/features/chart.js",
      viewportScope: "chart"
    )
    let idle = _WebFeatureManifest(id: "analytics-fixture", entry: "/features/analytics.js")

    _expectEqual(viewport._prefetchResources.count, 1)
    if case .viewport("chart") = viewport._prefetchResources[0].trigger {} else {
      _fail("A viewport-scoped feature must remain out of the idle queue")
    }
    if case .idle = idle._prefetchResources[0].trigger {} else {
      _fail("A feature without a route or viewport uses the bounded idle queue")
    }
  }
}
