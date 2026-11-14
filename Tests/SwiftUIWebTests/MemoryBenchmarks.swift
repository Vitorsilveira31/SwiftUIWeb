import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) @testable import SwiftUIWebFiber

/// Allocation telemetry tests intentionally use the same retained Fiber path
/// as the browser host.  The numbers are estimates at framework ownership
/// boundaries (not a replacement for a browser allocator profiler), which
/// makes the test usable on native, WASI and Embedded toolchains alike.
private struct MemoryRows: View {
  let values: [Int]
  var body: some View {
    ForEach(values, id: \.self) { value in
      Text("Row \(value)")
    }
  }
}

private struct MemoryStateView: View {
  @State var value = 0
  var body: some View {
    VStack {
      Text("Value \(value)")
      Button("Increment") { value += 1 }
    }
  }
}

private struct MemoryBindingView: View {
  @State var value = ""
  var body: some View {
    TextField("Name", text: $value)
  }
}

@Suite
@MainActor
final class MemoryBenchmarks {
  /// Run with `swift test -c release --filter MemoryBenchmarks` to get a
  /// compact, repeatable allocation/lifetime sample for a toolchain.
  @Test
  func testRuntimeMemorySnapshot() {
    _RuntimeMemoryMetrics.start()
    var tree: FiberTree? = FiberTree(MemoryStateView())
    let startup = _RuntimeMemoryMetrics.snapshot()
    print("startup,renderNodeLive=\(startup.renderNodeLive),fiberLive=\(startup.fiberLive),stateBoxes=\(startup.stateBoxAllocations),stateStorage=\(startup.stateStorageAllocations),liveObjects=\(startup.liveObjectCount),retainedNodeBytes=\(startup.retainedRenderNodeBytes)")
    for value in 1...25 {
      _ = tree?.update(MemoryRows(values: Array(0..<value)))
    }
    let snapshot = _RuntimeMemoryMetrics.snapshot()
    print("memory,allocations=\(snapshot.renderNodeAllocations),deallocations=\(snapshot.renderNodeDeallocations),renderNodeLive=\(snapshot.renderNodeLive),peakRenderNodeLive=\(snapshot.peakRenderNodeLive),fiberAllocations=\(snapshot.fiberAllocations),fiberLive=\(snapshot.fiberLive),bindingCells=\(snapshot.bindingCellLive),stateBoxes=\(snapshot.stateBoxAllocations),stateStorage=\(snapshot.stateStorageAllocations),stateEntries=\(snapshot.stateStoreEntries),dependencyEdges=\(snapshot.dependencyOwnerEdges),liveObjects=\(snapshot.liveObjectCount),arcEvents=\(snapshot.estimatedARCEvents),retainedNodeBytes=\(snapshot.retainedRenderNodeBytes),estimatedBytes=\(snapshot.estimatedLiveBytes)")
    if let metrics = tree?.metrics {
      print("representation,retainedFibers=\(metrics.retainedFiberNodes),retainedRenderNodes=\(metrics.retainedRenderNodeNodes),fiberChildEdges=\(metrics.retainedFiberChildEdges),renderNodeChildEdges=\(metrics.retainedRenderNodeChildEdges),retainedStructuralNodes=\(metrics.retainedStructuralNodes),structuralAllocations=\(metrics.structuralNodeAllocations),packedRecords=\(metrics.packedMutationRecords),packedBytes=\(metrics.packedMutationBytes),packedMaterializations=\(metrics.packedMutationMaterializations)")
      _expectEqual(metrics.retainedFiberNodes, metrics.retainedRenderNodeNodes)
      _expectGreaterThanOrEqual(metrics.retainedFiberChildEdges, metrics.retainedRenderNodeChildEdges)
    }
    _expectGreaterThan(snapshot.renderNodeAllocations, 0)
    _expectGreaterThan(snapshot.fiberAllocations, 0)
    _expectGreaterThan(snapshot.peakRenderNodeLive, 0)
    _expectGreaterThanOrEqual(snapshot.peakRenderNodeLive, snapshot.fiberLive)

    tree = nil
    let released = _RuntimeMemoryMetrics.snapshot()
    print("release,renderNodeLive=\(released.renderNodeLive),fiberLive=\(released.fiberLive),bindingCellLive=\(released.bindingCellLive),retainedNodeBytes=\(released.retainedRenderNodeBytes)")
    _expectEqual(released.renderNodeLive, 0, "released trees must not retain RenderNodes")
    _expectEqual(released.fiberLive, 0, "released trees must not retain Fibers")
    _expectEqual(released.bindingCellLive, 0, "released trees must not retain BindingCells")
    _expectEqual(released.retainedRenderNodeBytes, 0, "released trees must clear retained shape samples")
    _RuntimeMemoryMetrics.stop()
  }

  @Test
  func testLargeListRetainsOnlyCurrentTreeAfterRemoval() {
    _RuntimeMemoryMetrics.start()
    var tree: FiberTree? = FiberTree(MemoryRows(values: Array(0..<500)))
    let peak = _RuntimeMemoryMetrics.snapshot().peakRenderNodeLive
    _ = tree?.update(MemoryRows(values: [1, 2, 3]))
    // A second no-op commit consumes the previous mutation side table. This
    // models the browser host's end-of-frame release point rather than
    // mistaking intentional one-commit mutation retention for a leak.
    _ = tree?.update(MemoryRows(values: [1, 2, 3]))
    let afterRemoval = _RuntimeMemoryMetrics.snapshot()
    print("list-removal,peakRenderNodeLive=\(peak),liveAfterRemoval=\(afterRemoval.renderNodeLive),fiberLive=\(afterRemoval.fiberLive),estimatedBytes=\(afterRemoval.estimatedLiveBytes)")
    _expectGreaterThan(peak, afterRemoval.renderNodeLive)
    tree = nil
    _expectEqual(_RuntimeMemoryMetrics.snapshot().renderNodeLive, 0)
    _expectEqual(_RuntimeMemoryMetrics.snapshot().fiberLive, 0)
    _RuntimeMemoryMetrics.stop()
  }

  @Test
  func testBindingCellsAreReleasedWithTree() {
    _RuntimeMemoryMetrics.start()
    var tree: FiberTree? = FiberTree(MemoryBindingView())
    _expectGreaterThan(_RuntimeMemoryMetrics.snapshot().bindingCellLive, 0)
    _ = tree?.root
    tree = nil
    _expectEqual(_RuntimeMemoryMetrics.snapshot().bindingCellLive, 0)
    _RuntimeMemoryMetrics.stop()
  }

  @Test
  func testObservationTreeDisposeReleasesDependencyGraph() {
    _RuntimeMemoryMetrics.start()
    struct ObservationRoot: View {
      var body: some View { ForEach([0], id: \.self) { _ in Text("Observation") } }
    }
    var tree: FiberTree? = FiberTree(ObservationRoot())
    guard let owner = tree?.root.renderOwnerToken else {
      _RuntimeMemoryMetrics.stop()
      return _fail("observation root did not register an owner")
    }
    tree?.root.stateStore._ownerObservationDidChange(owner)
    let pendingBeforeRender = tree?._observationDiagnostics
    _expectEqual(pendingBeforeRender?.plan, _InvalidationPlan.subtree([owner]))
    _ = tree?.renderNode

    tree?._dispose()
    let disposed = tree?._observationDiagnostics
    _expectTrue(disposed?.disposed == true)
    _expectEqual(disposed?.stateStore.teardownCount, 1)
    if let disposed {
      _expectEqual(disposed.stateStore.dependencies.plan, .none)
    }
    _expectEqual(tree?._runtimeDiagnostics.dependencyEdges, 0)
    _expectEqual(_RuntimeMemoryMetrics.snapshot().dependencyOwnerEdges, 0)

    tree = nil
    let released = _RuntimeMemoryMetrics.snapshot()
    _expectEqual(released.renderNodeLive, 0)
    _expectEqual(released.fiberLive, 0)
    _RuntimeMemoryMetrics.stop()
  }

  @Test
  func testListScaleMemoryMatrix() {
    for count in [100, 1_000, 10_000] {
      _RuntimeMemoryMetrics.start()
      var tree: FiberTree? = FiberTree(MemoryRows(values: Array(0..<count)))
      let mounted = _RuntimeMemoryMetrics.snapshot()
      _ = tree?.update(MemoryRows(values: [0, 1, 2]))
      _ = tree?.update(MemoryRows(values: [0, 1, 2]))
      let settled = _RuntimeMemoryMetrics.snapshot()
      print("list-scale,count=\(count),startupLive=\(mounted.renderNodeLive),peakLive=\(mounted.peakRenderNodeLive),settledLive=\(settled.renderNodeLive),peakBytes=\(settled.peakRetainedRenderNodeBytes)")
      _expectLessThanOrEqual(settled.renderNodeLive, 8)
      tree = nil
      _expectEqual(_RuntimeMemoryMetrics.snapshot().renderNodeLive, 0)
      _RuntimeMemoryMetrics.stop()
    }
  }

}
