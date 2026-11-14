@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// `IndexSet` and the list-editing helpers built on it (`remove(atOffsets:)`, `move(fromOffsets:toOffset:)`, and
// `onDelete` / `onMove` on dynamic content). Foundation's shape on every host: a `SetAlgebra` of `Int` elements, so
// `IndexSet([1, 2])`, array literals and the set operations come from the protocol, as on Apple platforms.
@_spi(Renderer) import SwiftUIWebTransferable
public struct IndexSet: BidirectionalCollection, Hashable, SetAlgebra, Sendable {
  public typealias Element = Int
  public typealias ArrayLiteralElement = Int
  /// Sorted, disjoint, non-adjacent ranges, as Foundation keeps an index set: `IndexSet(integersIn: 3...)` is one range,
  /// not two billion elements.
  private var ranges: [Range<Int>] = []

  public init() {}
  public init(integer: IndexSet.Element) { insert(integer) }
  public init(integersIn range: Range<IndexSet.Element>) { if !range.isEmpty { ranges = [range] } }
  public init<R: RangeExpression>(integersIn range: R) where R.Bound == IndexSet.Element {
    // Foundation's bounds: an open end runs from 0, or up to the largest index.
    self.init(integersIn: range.relative(to: 0 ..< Int.max))
  }

  public var count: Int {
    var total = 0
    for range in ranges {
      // A range wider than Int (from a negative index to Int.max) has no Int count: it saturates like the sum.
      let (width, wide) = range.upperBound.subtractingReportingOverflow(range.lowerBound)
      if wide { return Int.max }
      let (sum, overflow) = total.addingReportingOverflow(width)
      if overflow { return Int.max }
      total = sum
    }
    return total
  }
  public var isEmpty: Bool { ranges.isEmpty }
  public var first: Element? { ranges.first?.lowerBound }
  public var last: Element? { ranges.last.map { $0.upperBound - 1 } }

  /// The first range whose upper bound is above `integer`, by binary search.
  private func position(above integer: Int) -> Int {
    var low = 0, high = ranges.count
    while low < high {
      let middle = (low + high) / 2
      if ranges[middle].upperBound <= integer { low = middle + 1 } else { high = middle }
    }
    return low
  }

  public func contains(_ integer: IndexSet.Element) -> Bool {
    let index = position(above: integer)
    return index < ranges.count && ranges[index].contains(integer)
  }
  @discardableResult public mutating func insert(_ integer: IndexSet.Element) -> (inserted: Bool, memberAfterInsert: IndexSet.Element) {
    // Int.max is past the largest index (Foundation's NSNotFound), so it cannot be a member.
    guard integer < Int.max, !contains(integer) else { return (false, integer) }
    // In place: the integer joins the range that ends at it, the one that starts after it, both, or neither.
    let index = position(above: integer)
    let joinsPrevious = index > 0 && ranges[index - 1].upperBound == integer
    let joinsNext = index < ranges.count && ranges[index].lowerBound == integer + 1
    switch (joinsPrevious, joinsNext) {
    case (true, true):
      ranges[index - 1] = ranges[index - 1].lowerBound ..< ranges[index].upperBound
      ranges.remove(at: index)
    case (true, false):
      ranges[index - 1] = ranges[index - 1].lowerBound ..< integer + 1
    case (false, true):
      ranges[index] = integer ..< ranges[index].upperBound
    case (false, false):
      ranges.insert(integer ..< integer + 1, at: index)
    }
    return (true, integer)
  }
  @discardableResult public mutating func remove(_ integer: IndexSet.Element) -> IndexSet.Element? {
    guard integer < Int.max, contains(integer) else { return nil }
    // In place: the range that holds it shrinks, splits in two, or goes.
    let index = position(above: integer)
    let range = ranges[index]
    let before = range.lowerBound ..< integer, after = integer + 1 ..< range.upperBound
    switch (before.isEmpty, after.isEmpty) {
    case (true, true): ranges.remove(at: index)
    case (false, true): ranges[index] = before
    case (true, false): ranges[index] = after
    case (false, false):
      ranges[index] = before
      ranges.insert(after, at: index + 1)
    }
    return integer
  }
  @discardableResult public mutating func update(with integer: IndexSet.Element) -> IndexSet.Element? {
    insert(integer).inserted ? nil : (contains(integer) ? integer : nil)
  }
  public mutating func removeAll() { ranges.removeAll() }

  public func union(_ other: IndexSet) -> IndexSet { IndexSet(ranges: Self.merged(ranges + other.ranges)) }
  public func intersection(_ other: IndexSet) -> IndexSet { IndexSet(ranges: Self.intersecting(ranges, other.ranges)) }
  public func symmetricDifference(_ other: IndexSet) -> IndexSet {
    IndexSet(ranges: Self.subtracting(Self.intersecting(ranges, other.ranges), from: Self.merged(ranges + other.ranges)))
  }
  public mutating func formUnion(_ other: IndexSet) { self = union(other) }
  public mutating func formIntersection(_ other: IndexSet) { self = intersection(other) }
  public mutating func formSymmetricDifference(_ other: IndexSet) { self = symmetricDifference(other) }

  private init(ranges: [Range<Int>]) { self.ranges = ranges }

  /// Sorted and joined: overlapping or touching ranges become one.
  private static func merged(_ input: [Range<Int>]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    for range in input.filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
      if let last = result.last, range.lowerBound <= last.upperBound {
        result[result.count - 1] = last.lowerBound ..< Swift.max(last.upperBound, range.upperBound)
      } else {
        result.append(range)
      }
    }
    return result
  }

  private static func intersecting(_ a: [Range<Int>], _ b: [Range<Int>]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    var i = 0, j = 0
    while i < a.count, j < b.count {
      let lower = Swift.max(a[i].lowerBound, b[j].lowerBound), upper = Swift.min(a[i].upperBound, b[j].upperBound)
      if lower < upper { result.append(lower ..< upper) }
      if a[i].upperBound < b[j].upperBound { i += 1 } else { j += 1 }
    }
    return result
  }

  /// `base` without the members of `removed`; both sorted and disjoint.
  private static func subtracting(_ removed: [Range<Int>], from base: [Range<Int>]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    var j = 0
    for range in base {
      var lower = range.lowerBound
      while j < removed.count, removed[j].upperBound <= lower { j += 1 }
      var k = j
      while k < removed.count, removed[k].lowerBound < range.upperBound {
        if removed[k].lowerBound > lower { result.append(lower ..< removed[k].lowerBound) }
        lower = Swift.max(lower, removed[k].upperBound)
        k += 1
      }
      if lower < range.upperBound { result.append(lower ..< range.upperBound) }
    }
    return result
  }

  /// A position in the set, as Foundation's: the member and the range that holds it. Iterating goes range by range, so an
  /// open range is walked lazily instead of being materialized.
  public struct Index: CustomStringConvertible, Comparable, Hashable, Sendable {
    fileprivate let value: Int
    fileprivate let rangeIndex: Int

    public var description: String { "index \(value) [range #\(rangeIndex)]" }
    public static func < (lhs: IndexSet.Index, rhs: IndexSet.Index) -> Bool {
      lhs.rangeIndex != rhs.rangeIndex ? lhs.rangeIndex < rhs.rangeIndex : lhs.value < rhs.value
    }
  }

  public var startIndex: IndexSet.Index { ranges.isEmpty ? endIndex : Index(value: ranges[0].lowerBound, rangeIndex: 0) }
  public var endIndex: IndexSet.Index { Index(value: 0, rangeIndex: ranges.count) }
  public subscript(index: IndexSet.Index) -> IndexSet.Element { index.value }

  public func index(after i: IndexSet.Index) -> IndexSet.Index {
    if i.value + 1 < ranges[i.rangeIndex].upperBound { return Index(value: i.value + 1, rangeIndex: i.rangeIndex) }
    let next = i.rangeIndex + 1
    return next < ranges.count ? Index(value: ranges[next].lowerBound, rangeIndex: next) : endIndex
  }

  public func index(before i: IndexSet.Index) -> IndexSet.Index {
    if i.rangeIndex < ranges.count, i.value > ranges[i.rangeIndex].lowerBound {
      return Index(value: i.value - 1, rangeIndex: i.rangeIndex)
    }
    let previous = i.rangeIndex - 1
    return Index(value: ranges[previous].upperBound - 1, rangeIndex: previous)
  }

  /// The members below `limit`, in descending order: what a collection of `limit` elements can remove or move.
  fileprivate func offsets(below limit: Int) -> [Int] {
    var result: [Int] = []
    for range in ranges.reversed() {
      let upper = Swift.min(range.upperBound, limit), lower = Swift.max(range.lowerBound, 0)
      if lower < upper { result.append(contentsOf: (lower ..< upper).reversed()) }
    }
    return result
  }
}

public extension RangeReplaceableCollection {
  mutating func remove(atOffsets offsets: IndexSet) {
    // Only the offsets inside the collection are visited, so a set such as `IndexSet(integersIn: 3...)` is not walked
    // to its end.
    for offset in offsets.offsets(below: count) {
      remove(at: index(startIndex, offsetBy: offset))
    }
  }
}

public extension MutableCollection where Self: RangeReplaceableCollection {
  mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    let ascending = Array(source.offsets(below: count).reversed())
    let moving = ascending.map { self[index(startIndex, offsetBy: $0)] }
    let before = ascending.filter { $0 < destination }.count
    remove(atOffsets: source)
    let position = Swift.max(0, Swift.min(count, destination - before))
    insert(contentsOf: moving, at: index(startIndex, offsetBy: position))
  }
}

/// A view generated from a collection, such as `ForEach`: the rows a list deletes and moves.
public protocol DynamicViewContent<Data>: View {
  associatedtype Data: Collection
  var data: Data { get }
}

extension ForEach: DynamicViewContent where Content: View {}

/// A modifier on dynamic content keeps the content's collection, so `.id(_:)` and the like do not hide `onDelete`.
extension ModifiedContent where Content: DynamicViewContent {
  // Declared outside the conformance below, which would otherwise make the property main-actor isolated.
  public var data: Content.Data {
    nonisolated(unsafe) let content = self.content
    return _assumeMainActor { content.data }
  }
}

extension ModifiedContent: DynamicViewContent where Content: DynamicViewContent {}

public extension DynamicViewContent {
  /// Swipe-to-delete / edit-mode deletion of rows. The row actions of a browser list are the application's own
  /// buttons (`swipeActions`); the callback is accepted so the source compiles.
  nonisolated func onDelete(perform action: Optional<(IndexSet) -> Void>) -> some DynamicViewContent { self }
  nonisolated func onMove(perform action: Optional<(IndexSet, Int) -> Void>) -> some DynamicViewContent { self }
}

public extension View {
  nonisolated func deleteDisabled(_ isDisabled: Bool) -> some View { self }
  nonisolated func moveDisabled(_ isDisabled: Bool) -> some View { self }
}
