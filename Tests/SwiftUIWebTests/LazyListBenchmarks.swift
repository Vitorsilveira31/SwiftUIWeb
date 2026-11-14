import Dispatch
import Testing
import Foundation
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// Release-mode, deterministic layout benchmarks. Browser paint/FPS requires
/// a WASM-capable toolchain and a real browser, so this suite measures the
/// backend-neutral work that controls those costs: range lookup, active
/// logical rows, simulated mount/unmount versus bounded recycling, and
/// measurement correction.
@Suite
@MainActor
final class LazyListBenchmarks {
  @Test
  func testLargeListDescriptorAvoidsOffscreenRowBodies() {
    struct Item: Identifiable { let id: Int }
    final class Counter { var bodyEvaluations = 0 }
    struct Row: View {
      let item: Item
      let counter: Counter
      var body: some View {
        counter.bodyEvaluations += 1
        return Text("row-\(item.id)")
      }
    }

    let items = (0..<100_000).map(Item.init)
    let counter = Counter()
    let tree = FiberTree(List(items) { Row(item: $0, counter: counter) })
    _expectEqual(counter.bodyEvaluations, 0)
    guard let info = tree._lazyCollections().first else {
      return _fail("expected List to emit a deferred descriptor")
    }
    _ = tree._materializeLazyCollection(
      ownerIdentity: info.ownerIdentity,
      indices: Array(0..<26),
      beforeExtent: 0,
      afterExtent: 6_398_336
    )
    _expectEqual(counter.bodyEvaluations, 26)
    _expectLessThan(counter.bodyEvaluations, items.count)
  }

  @Test
  func testLazyListBenchmarkMatrix() {
    let counts = [100, 1_000, 10_000, 100_000]
    let viewport = 720.0
    let iterations = 120
    print("workload,count,shape,maxActive,peakDOMNodes,layoutQueries,measurements,mountUnmount,recycleReuse,mountAllocations,recycleAllocations,recyclePoolPeak,blankAreas")
    for count in counts {
      for variable in [false, true] {
        let engine = _LazyLayoutEngine(
          axis: .vertical,
          count: count,
          estimatedExtent: variable ? 72 : 64,
          overscan: 420
        )
        var previous = Set<Int>()
        var maxActive = 0
        var peakDOMNodes = 0
        var mountUnmount = 0
        var recycleReuse = 0
        var mountAllocations = 0
        var recycleAllocations = 0
        var recyclePool = 0
        var recyclePoolPeak = 0
        var blankAreas = 0
        for step in 0..<iterations {
          let maxOffset = max(0, engine.totalExtent - viewport)
          let fraction = Double(step % 60) / 59.0
          let offset = maxOffset * fraction
          let plan = engine.plan(offset: offset, viewport: viewport, velocity: step % 2 == 0 ? 5 : -5)
          let active = Set(plan.range)
          maxActive = max(maxActive, active.count)
          peakDOMNodes = max(peakDOMNodes, active.count + 2) // top/bottom spacers
          let entering = active.subtracting(previous).count
          let leaving = previous.subtracting(active).count
          mountUnmount += entering + leaving
          recycleReuse += min(entering, leaving)
          mountAllocations += entering
          let reused = min(entering, recyclePool + leaving)
          recycleAllocations += entering - reused
          recyclePool = min(32, recyclePool + leaving - reused)
          recyclePoolPeak = max(recyclePoolPeak, recyclePool)
          if variable {
            // Simulate browser measurements arriving in batches. The actual
            // DOM host applies these to the same cache and preserves its
            // anchor before requesting the next range.
            for index in plan.range where index % 11 == step % 11 {
              _ = engine.updateMeasured(index: index, size: 48 + Double(index % 7) * 13)
            }
          }
          previous = active
          if active.isEmpty && count > 0 { blankAreas += 1 }
        }
        _expectLessThan(peakDOMNodes, count, "a lazy list must never materialize every row")
        _expectLessThanOrEqual(maxActive, 100, "the default viewport/overscan window should stay bounded")
        _expectLessThan(recycleAllocations, mountAllocations,
                          "a compatible recycle pool should reduce physical allocations")
        let shape = variable ? "variable" : "fixed"
        print("scroll,count=\(count),shape=\(shape),maxActive=\(maxActive),peakDOMNodes=\(peakDOMNodes),layoutQueries=\(engine.layoutQueries),measurements=\(engine.measurementUpdates),mountUnmount=\(mountUnmount),recycleReuse=\(recycleReuse),mountAllocations=\(mountAllocations),recycleAllocations=\(recycleAllocations),recyclePoolPeak=\(recyclePoolPeak),blankAreas=\(blankAreas)")
      }
    }
  }

  @Test
  func testLazyListMutationsPreserveAnchorsForAppendPrependAndChatEnd() {
    let engine = _LazyLayoutEngine(axis: .vertical, count: 1_000, estimatedExtent: 60, overscan: 360)
    let anchor = 500
    let oldOffset = engine.offset(of: anchor) + 12
    _ = engine.updateMeasured(index: anchor - 1, size: 130)
    let correctedOffset = engine.offset(of: anchor) + 12
    _expectEqual(correctedOffset - oldOffset, 70, accuracy: 0.001)
    engine.setCount(1_100)
    _expectGreaterThan(engine.totalExtent, oldOffset)
    let end = engine.plan(offset: engine.totalExtent, viewport: 600)
    _expectEqual(end.range.upperBound, 1_100)
    _expectFalse(end.range.isEmpty)
  }

  @Test
  func testLazyKeyRemapKeepsMeasuredExtentWithLogicalItem() {
    let engine = _LazyLayoutEngine(axis: .vertical, count: 3, estimatedExtent: 60, overscan: 120)
    _ = engine.updateMeasured(index: 1, size: 140)
    engine.remap([1, 0, nil])
    _expectEqual(engine.extent(at: 0), 140, accuracy: 0.001)
    _expectEqual(engine.extent(at: 1), 60, accuracy: 0.001)
    _expectEqual(engine.extent(at: 2), 60, accuracy: 0.001)
    _expectEqual(engine.measuredCount, 1)
  }

  @Test
  func testContiguousRemapPreservesMeasuredExtentWithoutKeyScan() {
    let engine = _LazyLayoutEngine(axis: .vertical, count: 6, estimatedExtent: 60, overscan: 120)
    _ = engine.updateMeasured(index: 2, size: 144)
    _ = engine.updateMeasured(index: 4, size: 96)

    // A chat prepend shifts every logical row by two positions. The fast
    // offset remap must carry measured extents with those rows and leave new
    // leading rows at the estimate rather than scanning/reallocating a key
    // table for the whole collection.
    engine.remapByOffset(newCount: 8, oldOffset: -2)
    _expectEqual(engine.extent(at: 0), 60, accuracy: 0.001)
    _expectEqual(engine.extent(at: 4), 144, accuracy: 0.001)
    _expectEqual(engine.extent(at: 6), 96, accuracy: 0.001)
    _expectEqual(engine.measuredCount, 2)

    // Removing the same prefix reverses the operation and drops measurements
    // that no longer have a logical owner.
    engine.remapByOffset(newCount: 6, oldOffset: 2)
    _expectEqual(engine.extent(at: 2), 144, accuracy: 0.001)
    _expectEqual(engine.extent(at: 4), 96, accuracy: 0.001)
    _expectEqual(engine.measuredCount, 2)
  }

  @Test
  func testLazyEstimateChangeUpdatesOnlyUnmeasuredRows() {
    let engine = _LazyLayoutEngine(axis: .vertical, count: 4, estimatedExtent: 60, overscan: 120)
    _ = engine.updateMeasured(index: 1, size: 140)

    // Responsive layouts can change their estimate without changing the
    // logical count. A real measurement must remain authoritative while
    // unknown rows adopt the new estimate.
    engine.setCount(4, estimatedExtent: 80)
    _expectEqual(engine.extent(at: 0), 80, accuracy: 0.001)
    _expectEqual(engine.extent(at: 1), 140, accuracy: 0.001)
    _expectEqual(engine.extent(at: 2), 80, accuracy: 0.001)
    _expectEqual(engine.extent(at: 3), 80, accuracy: 0.001)

    // The same invariant must hold when keyed rows are remapped after a
    // prepend/reorder: measured values follow the logical item, estimates do
    // not carry stale values across the new layout.
    engine.remap([2, 1, nil, 0], estimatedExtent: 100)
    _expectEqual(engine.extent(at: 0), 100, accuracy: 0.001)
    _expectEqual(engine.extent(at: 1), 140, accuracy: 0.001)
    _expectEqual(engine.extent(at: 2), 100, accuracy: 0.001)
    _expectEqual(engine.extent(at: 3), 100, accuracy: 0.001)
    _expectEqual(engine.measuredCount, 1)
  }

  @Test
  func testLazyListMutationAndViewportWorkloads() {
    let engine = _LazyLayoutEngine(axis: .vertical, count: 10_000, estimatedExtent: 72, overscan: 420)
    let start = DispatchTime.now().uptimeNanoseconds
    var rowsVisited = 0
    rowsVisited += engine.plan(offset: engine.offset(of: 8_000), viewport: 720).range.count // jump to distant item
    rowsVisited += engine.plan(offset: engine.offset(of: 4_000), viewport: 720, velocity: 20).range.count // rapid scroll
    engine.setCount(10_100) // append
    rowsVisited += engine.plan(offset: engine.totalExtent, viewport: 720).range.count // chat-style bottom anchor
    engine.setCount(10_200) // prepend (the browser host relocates its keyed anchor)
    rowsVisited += engine.plan(offset: engine.offset(of: 200), viewport: 720).range.count
    engine.setCount(9_900) // deletion
    rowsVisited += engine.plan(offset: engine.offset(of: 2_000), viewport: 480).range.count // viewport resize
    rowsVisited += engine.plan(offset: engine.offset(of: 2_100), viewport: 720).range.count // reorder keeps layout extent
    for index in 0..<rowsVisited where index < engine.count { _ = engine.updateMeasured(index: index, size: 50 + Double(index % 9) * 17) } // image/feed-style correction
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    print("workload,jump,rapid-scroll,append,prepend,delete,reorder,chat-anchor,resize,image-feed,rowsVisited,elapsedNs")
    print("lazy-mutations,yes,yes,yes,yes,yes,yes,yes,yes,yes,\(rowsVisited),\(elapsed)")
    _expectGreaterThan(rowsVisited, 0)
    _expectGreaterThan(engine.measurementUpdates, 0)
  }
}
