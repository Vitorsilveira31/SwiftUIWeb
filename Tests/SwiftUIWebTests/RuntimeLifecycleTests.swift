import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite(.serialized)
@MainActor
struct RuntimeLifecycleTests {
  @Test
  func stateStoreObservationDiagnosticsCoalesceAndTeardown() {
    let store = StateStore()
    store._recordPublishedObservation(_StateSourceID(rawValue: 5))
    store._ownerObservationDidChange(17)
    store._ownerObservationDidChange(17)

    let pending = store._observationDiagnostics
    _expectEqual(pending.accessCount, 1)
    _expectEqual(pending.invalidationCount, 2)
    _expectEqual(pending.coalescedInvalidationCount, 1)
    _expectEqual(pending.plan, .subtree([17]))

    store._dispose()
    store._dispose()
    let disposed = store._observationDiagnostics
    _expectTrue(disposed.isDisposed)
    _expectEqual(disposed.teardownCount, 1)
    _expectEqual(disposed.plan, .none)
  }

  @Test
  func stateStoreDisposeIsIdempotent() {
    let store = StateStore()
    var invalidations = 0
    store.setInvalidationHandler { invalidations += 1 }

    store._dispose()
    store._dispose()

    _expectTrue(store._isDisposed)
    _expectEqual(invalidations, 0)
    store._beginRenderPass()
    store._recordRead(_StateSourceID(rawValue: 91))
    store._endRenderPass(provenLeafSources: [])
    _expectFalse(store._dependencies.isStructural(_StateSourceID(rawValue: 91)), "disposed stores must reject new dependency reads")
    _expectEqual(store._observationDiagnostics.plan, .none)
  }

  @Test
  func fiberTreeDisposeIsIdempotent() {
    let tree = FiberTree(Text("lifecycle"))
    let retainedNode = tree.renderNode
    let diagnostics = tree._runtimeDiagnostics
    _expectEqual(Int(diagnostics.liveNodes), tree._liveStructuralNodeCount)
    tree._dispose()
    tree._dispose()
    _expectTrue(tree._isDisposed)
    _expectTrue(tree._observationDiagnostics.disposed)
    _expectEqual(tree._observationDiagnostics.plan, .none)
    _expectTrue(tree.update(Text("ignored")).isEmpty)
    _expectTrue(tree.renderNode === retainedNode)
  }
}
