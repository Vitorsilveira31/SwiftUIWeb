import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite(.serialized)
struct LazyLayoutEngineTests {
  private func extents(_ layout: _LazyLayoutEngine) -> [Double] {
    (0..<layout.count).map { layout.extent(at: $0) }
  }

  @Test
  func emptyBoundsAndNonFiniteInputs() {
    let x = _LazyLayoutEngine(axis: .vertical, count: 0, estimatedExtent: .nan, overscan: .infinity)
    _expectEqual(x.totalExtent, 0)
    _expectEqual(x.index(at: 0), 0)
    _expectEqual(x.plan(offset: 0, viewport: 1).range.upperBound, 0)
    x.setCount(10)
    _expectEqual(x.totalExtent, 10)
    _expectEqual(x.offset(of: .min), 0)
    _expectEqual(x.offset(of: .max), 10)
    _expectEqual(x.extent(at: -1), 1)
    _expectEqual(x.index(at: .nan), 0)
    _expectFalse(x.updateMeasured(index: -1, size: 2).changed)
    _expectFalse(x.updateMeasured(index: 0, size: .nan).changed)
  }

  @Test
  func measurementThresholdDoesNotMoveAnAnchor() {
    let x = _LazyLayoutEngine(axis: .vertical, count: 4, estimatedExtent: 40, overscan: 0)
    let ignored = x.updateMeasured(index: 0, size: 40.2)
    _expectFalse(ignored.changed)
    _expectEqual(ignored.delta, 0)
    _expectEqual(ignored.measuredCount, 1)
    _expectEqual(x.totalExtent, 160)
    let applied = x.updateMeasured(index: 0, size: 42)
    _expectEqual(applied.delta, 2)
    _expectEqual(x.totalExtent, 162)
  }

  @Test
  func remapAndEstimatesPreserveMeasuredRowsOnly() {
    let x = _LazyLayoutEngine(axis: .vertical, count: 3, estimatedExtent: 10, overscan: 0)
    x.updateMeasured(index: 1, size: 25)
    x.remap([1, nil, 0], estimatedExtent: 20)
    _expectEqual(extents(x), [25, 20, 20])
    x.setCount(4, estimatedExtent: 30)
    _expectEqual(extents(x), [25, 30, 30, 30])
    x.remapByOffset(newCount: 5, oldOffset: -1, estimatedExtent: 40)
    _expectEqual(extents(x), [40, 25, 40, 40, 40])
    x.remapByOffset(newCount: 1, oldOffset: .max)
    _expectEqual(extents(x), [40])
    _expectEqual(x.measuredCount, 0)
    x.remapByOffset(newCount: 1, oldOffset: .min)
    _expectEqual(extents(x), [40])
  }

  @Test
  func prefixAndInverseMatchALinearOracle() {
    let x = _LazyLayoutEngine(axis: .vertical, count: 513, estimatedExtent: 20, overscan: 10)
    for i in 0..<513 {
      let size = Double((i * 37) % 121) + 1
      x.updateMeasured(index: i, size: size)
    }
    var sum = 0.0
    for (i, size) in extents(x).enumerated() {
      _expectTrue(abs(x.offset(of: i) - sum) < 0.0001)
      _expectEqual(x.index(at: sum), i)
      _expectEqual(x.index(at: sum + size * 0.5), i)
      sum += size
    }
    _expectEqual(x.totalExtent, sum)
    _expectEqual(x.index(at: sum + 10), 512)
  }

  @Test
  func largeListEstimateUpdateAndPlanning() {
    let x = _LazyLayoutEngine(axis: .vertical, count: 100_000, estimatedExtent: 40, overscan: 400)
    x.updateMeasured(index: 50_000, size: 75)
    x.setCount(100_000, estimatedExtent: 60)
    _expectEqual(x.totalExtent, 6_000_015)
    let p = x.plan(offset: 3_000_000, viewport: 600, velocity: 1)
    _expectLessThan(p.range.count, 30)
    _expectEqual(x.rangeChanges, 1)
    x.plan(offset: 3_000_000, viewport: 600, velocity: 1)
    _expectEqual(x.rangeChanges, 1)
    _expectTrue(abs(p.beforeExtent + (x.offset(of: p.range.upperBound) - p.beforeExtent) + p.afterExtent - p.totalExtent) < 0.0001)
  }

  @Test
  func noOpResizeAndVelocityDirectionKeepRangesStable() {
    let x = _LazyLayoutEngine(axis: .vertical, count: 8, estimatedExtent: 10, overscan: 4)
    x.overscan = -10
    _expectEqual(x.overscan, 0)
    x.setCount(8)
    _expectEqual(x.rangeChanges, 0)
    for velocity in [1.0, -1.0, 0.0] {
      let p = x.plan(offset: 20, viewport: 10, velocity: velocity)
      _expectLessThanOrEqual(p.range.lowerBound, p.range.upperBound)
    }
    _expectGreaterThanOrEqual(x.rangeChanges, 1)
    _expectEqual(x.layoutQueries, 3)
  }

  @Test
  func countersAndRemapFollowMeasurements() {
    let x = _LazyLayoutEngine(axis: .vertical, count: 1000, estimatedExtent: 40, overscan: 400)
    _expectEqual(x.updateMeasured(index: 2, size: 40.2).delta, 0)
    _expectEqual(x.updateMeasured(index: 2, size: 60).delta, 20)
    _expectEqual(x.measurementUpdates, 1)
    _expectEqual(x.totalExtent, 40_020)
    x.setCount(1000, estimatedExtent: 50)
    _expectEqual(x.totalExtent, 50_010)
    x.remap([0, 1, 2])
    _expectEqual(x.totalExtent, 160)
    _expectEqual(x.count, 3)
  }

  @Test
  func measurementReturnsOnlyTheAppliedAnchorDelta() {
    let layout = _LazyLayoutEngine(axis: .vertical, count: 4, estimatedExtent: 40)
    let ignored = layout.updateMeasured(index: 0, size: 40.2)
    _expectFalse(ignored.changed)
    _expectEqual(ignored.delta, 0)
    _expectEqual(layout.totalExtent, 160)
    let changed = layout.updateMeasured(index: 0, size: 42)
    _expectTrue(changed.changed)
    _expectEqual(changed.delta, 2)
    _expectEqual(layout.totalExtent, 162)
  }

  @Test
  func lazyResizeRemapAndPrefixLookup() {
    let layout = _LazyLayoutEngine(axis: .vertical, count: 3, estimatedExtent: 10)
    layout.updateMeasured(index: 1, size: 25)
    layout.remap([1, nil, 0], estimatedExtent: 20)
    _expectEqual(layout.totalExtent, 65)
    layout.setCount(4, estimatedExtent: 30)
    _expectEqual(layout.totalExtent, 115)
    _expectEqual(layout.offset(of: 2), 55)
    _expectEqual(layout.index(at: 55), 2)
    layout.remapByOffset(newCount: 5, oldOffset: -1, estimatedExtent: 40)
    _expectEqual(layout.totalExtent, 185)
    _expectEqual(layout.measuredCount, 1)
    layout.remapByOffset(newCount: 1, oldOffset: Int.max)
    _expectEqual(layout.totalExtent, 40)
    layout.remapByOffset(newCount: 1, oldOffset: Int.min)
    _expectEqual(layout.totalExtent, 40)
  }

  @Test
  func largeReestimateKeepsMeasuredRows() {
    let layout = _LazyLayoutEngine(axis: .vertical, count: 100_000, estimatedExtent: 40)
    layout.updateMeasured(index: 50_000, size: 75)
    layout.setCount(100_000, estimatedExtent: 60)
    _expectEqual(layout.totalExtent, 6_000_015)
    let plan = layout.plan(offset: 3_000_000, viewport: 600, velocity: 1)
    _expectLessThan(plan.range.count, 30)
    _expectEqual(plan.totalExtent, layout.totalExtent)
  }

  @Test
  func indexAtAnOffsetRoundingToTheTotalReadsTheLastRow() {
    // Two 1e20-point rows: the clamped target rounds to the total, so no running sum passes it.
    let layout = _LazyLayoutEngine(axis: .vertical, count: 2, estimatedExtent: 1e20, overscan: 0)
    _expectEqual(layout.totalExtent, 2e20)
    _expectEqual(layout.index(at: 1e300), 1)
  }
}
