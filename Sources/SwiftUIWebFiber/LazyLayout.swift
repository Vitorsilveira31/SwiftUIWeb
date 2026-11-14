@_spi(Renderer) import SwiftUIWebCore

/// A compact, backend-neutral layout cache used by browser lazy containers.
/// It deliberately contains no DOM or JavaScript types, so static/WASI hosts
/// can compile the same collection metadata and Embedded Swift avoids pulling
/// in reflection or hash-table based layout state.
@_spi(Renderer) public struct _LazyRangePlan: Sendable {
  public let range: Range<Int>
  public let beforeExtent: Double
  public let afterExtent: Double
  public let totalExtent: Double

  public init(range: Range<Int>, beforeExtent: Double, afterExtent: Double, totalExtent: Double) {
    self.range = range
    self.beforeExtent = beforeExtent
    self.afterExtent = afterExtent
    self.totalExtent = totalExtent
  }
}

@_spi(Renderer) public struct _LazyMeasurementResult: Sendable {
  public let changed: Bool
  public let delta: Double
  public let measuredCount: Int

  public init(changed: Bool, delta: Double, measuredCount: Int) {
    self.changed = changed
    self.delta = delta
    self.measuredCount = measuredCount
  }
}

/// Numeric layout of a lazy list: one extent per row (the estimate until the row is measured), summed in blocks so
/// an offset or an inverse lookup touches at most one block of rows plus a binary search over the block sums.
@_spi(Renderer) public final class _LazyLayoutEngine {
  private static let block = 64

  public let axis: _LazyAxis
  private var extents: [Double]
  private var measured: [Bool]
  /// `prefixes[b]` is the sum of the complete blocks before block `b`, with a leading zero.
  private var prefixes: [Double] = []
  private var lastRange: Range<Int>?
  private var overscanExtent: Double
  public private(set) var estimatedExtent: Double
  public private(set) var measuredCount = 0
  public private(set) var layoutQueries = 0
  public private(set) var measurementUpdates = 0
  public private(set) var rangeChanges = 0
  public var count: Int { extents.count }
  // `rebuild` (run by init) always leaves the leading zero, so the last block sum exists.
  public var totalExtent: Double { prefixes[prefixes.count - 1] }
  public var overscan: Double {
    get { overscanExtent }
    set { overscanExtent = Self.nonNegative(newValue) }
  }

  public init(axis: _LazyAxis, count: Int, estimatedExtent: Double, overscan: Double = 400) {
    self.axis = axis
    let estimate = Self.positive(estimatedExtent)
    self.estimatedExtent = estimate
    overscanExtent = Self.nonNegative(overscan)
    extents = [Double](repeating: estimate, count: max(0, count))
    measured = [Bool](repeating: false, count: max(0, count))
    rebuild()
  }

  /// A non-finite or sub-point extent reads as one point; a non-finite overscan as none.
  private static func positive(_ value: Double) -> Double { value.isFinite ? max(value, 1) : 1 }
  private static func nonNegative(_ value: Double) -> Double { value.isFinite ? max(value, 0) : 0 }
  private static func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }

  public func setCount(_ newCount: Int, estimatedExtent: Double? = nil) {
    let newCount = max(0, newCount)
    let next = estimatedExtent.map(Self.positive) ?? self.estimatedExtent
    let changed = abs(next - self.estimatedExtent) > 0.0001
    self.estimatedExtent = next
    if newCount == count && !changed { return }
    // One linear rewrite and one prefix rebuild; patching the prefixes per row is quadratic in a large list.
    if changed { for index in extents.indices where !measured[index] { extents[index] = next } }
    let oldCount = count
    if newCount != oldCount { lastRange = nil }
    if newCount < oldCount {
      extents.removeLast(oldCount - newCount)
      measured.removeLast(oldCount - newCount)
    } else {
      extents.append(contentsOf: repeatElement(next, count: newCount - oldCount))
      measured.append(contentsOf: repeatElement(false, count: newCount - oldCount))
    }
    measuredCount = measured.reduce(0) { $0 + ($1 ? 1 : 0) }
    rebuild()
  }

  /// `newToOld[i]` is the previous index of the row now at `i`, or nil for a new row.
  public func remap(_ newToOld: [Int?], estimatedExtent: Double? = nil) {
    remap(count: newToOld.count, estimatedExtent: estimatedExtent) { newToOld[$0] }
  }

  public func remapByOffset(newCount: Int, oldOffset: Int, estimatedExtent: Double? = nil) {
    remap(count: max(0, newCount), estimatedExtent: estimatedExtent) {
      let (old, overflow) = $0.addingReportingOverflow(oldOffset)
      return overflow ? nil : old
    }
  }

  /// Keeps the extent of every row that maps to a measured previous row; the others read as the estimate.
  private func remap(count newCount: Int, estimatedExtent: Double?, oldIndex: (Int) -> Int?) {
    let estimate = estimatedExtent.map(Self.positive) ?? self.estimatedExtent
    var nextExtents = [Double](repeating: estimate, count: newCount)
    var nextMeasured = [Bool](repeating: false, count: newCount)
    var nextMeasuredCount = 0
    for index in 0..<newCount {
      if let old = oldIndex(index), old >= 0, old < extents.count, measured[old] {
        nextExtents[index] = extents[old]
        nextMeasured[index] = true
        nextMeasuredCount += 1
      }
    }
    extents = nextExtents
    measured = nextMeasured
    measuredCount = nextMeasuredCount
    self.estimatedExtent = estimate
    lastRange = nil
    rebuild()
  }

  public func extent(at index: Int) -> Double {
    index >= 0 && index < count ? extents[index] : estimatedExtent
  }

  /// Records a row's measured size. A change of a quarter point or less is stored as measured but reported as
  /// unchanged, so it never moves the scroll anchor.
  @discardableResult public func updateMeasured(index: Int, size: Double) -> _LazyMeasurementResult {
    guard index >= 0, index < count, size.isFinite else {
      return _LazyMeasurementResult(changed: false, delta: 0, measuredCount: measuredCount)
    }
    let next = Self.positive(size)
    let delta = next - extents[index]
    let changed = abs(delta) > 0.25
    if changed {
      extents[index] = next
      for block in index / Self.block + 1..<prefixes.count { prefixes[block] += delta }
      measurementUpdates += 1
    }
    if !measured[index] {
      measured[index] = true
      measuredCount += 1
    }
    return _LazyMeasurementResult(changed: changed, delta: changed ? delta : 0, measuredCount: measuredCount)
  }

  public func offset(of index: Int) -> Double {
    let row = min(max(index, 0), count)
    let block = row / Self.block
    var result = prefixes[block]
    for index in block * Self.block..<row { result += extents[index] }
    return result
  }

  /// The row containing `offset`, clamped to the first and last rows.
  public func index(at offset: Double) -> Int {
    if extents.isEmpty { return 0 }
    let target = min(max(Self.finite(offset), 0), max(totalExtent - 0.0001, 0))
    let blocks = prefixes.count - 1
    var low = 0
    var high = blocks
    while low < high {
      let middle = low + (high - low) / 2
      if target < prefixes[middle + 1] { high = middle } else { low = middle + 1 }
    }
    let block = min(low, blocks - 1)
    let start = block * Self.block
    var cursor = prefixes[block]
    for index in start..<min(count, start + Self.block) {
      cursor += extents[index]
      if target < cursor { return index }
    }
    return count - 1
  }

  /// The rows to materialize for a viewport: the visible rows plus the overscan, which is larger on the side the
  /// scroll is heading toward.
  public func plan(offset scrollOffset: Double, viewport: Double, velocity: Double = 0) -> _LazyRangePlan {
    layoutQueries += 1
    if extents.isEmpty { return _LazyRangePlan(range: 0..<0, beforeExtent: 0, afterExtent: 0, totalExtent: 0) }
    let position = min(max(Self.finite(scrollOffset), 0), max(totalExtent - 1, 0))
    let length = Self.positive(viewport)
    let (leading, trailing) = velocity > 0.1 ? (0.65, 1.35) : velocity < -0.1 ? (1.35, 0.65) : (1.0, 1.0)
    let start = index(at: max(position - overscanExtent * leading, 0))
    let end = min(index(at: position + length + overscanExtent * trailing) + 1, count)
    let range = start..<max(end, start)
    if lastRange != range {
      rangeChanges += 1
      lastRange = range
    }
    return _LazyRangePlan(
      range: range,
      beforeExtent: offset(of: start),
      afterExtent: max(totalExtent - offset(of: end), 0),
      totalExtent: totalExtent
    )
  }

  private func rebuild() {
    let blocks = (count + Self.block - 1) / Self.block
    prefixes = [Double](repeating: 0, count: blocks + 1)
    for block in 0..<blocks {
      var sum = 0.0
      for index in block * Self.block..<min(count, (block + 1) * Self.block) { sum += extents[index] }
      prefixes[block + 1] = prefixes[block] + sum
    }
  }
}
