import Testing
import Foundation
@testable import SwiftUIWeb

/// `IndexSet` keeps ranges, as Foundation does: an open range is one entry, and the set operations agree with a `Set`.
@Suite
struct IndexSetRangeTests {
  @Test
  func anOpenRangeIsHeldAsOneRange() {
    let open = IndexSet(integersIn: 3...)
    #expect(open.first == 3)
    #expect(open.last == Int.max - 1)
    #expect(open.contains(1_000_000_000_000 % Int.max))
    #expect(!open.contains(2))
    #expect(open.count == Int.max - 3)
    var items = Array(0 ..< 6)
    items.remove(atOffsets: open)
    #expect(items == [0, 1, 2])
    #expect(IndexSet(integersIn: ..<3).map { $0 } == [0, 1, 2])
    // A collection, as Foundation's: walked forward and back by index.
    let gaps = IndexSet([1, 2, 5])
    #expect(Array(gaps.reversed()) == [5, 2, 1])
    #expect(gaps[gaps.index(after: gaps.startIndex)] == 2)
    #expect(gaps.index(before: gaps.endIndex) == gaps.indices.last)
  }

  @Test
  func setOperationsMatchASet() {
    var seed: UInt64 = 7
    func random(_ bound: Int) -> Int {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return Int((seed >> 33) % UInt64(bound))
    }
    for _ in 0 ..< 200 {
      var a = IndexSet(), b = IndexSet()
      var setA = Set<Int>(), setB = Set<Int>()
      for _ in 0 ..< 20 {
        let x = random(40), y = random(40)
        a.insert(x); setA.insert(x)
        b.insert(y); setB.insert(y)
      }
      let removed = random(40)
      a.remove(removed); setA.remove(removed)
      #expect(Array(a) == setA.sorted())
      #expect(Array(a.union(b)) == setA.union(setB).sorted())
      #expect(Array(a.intersection(b)) == setA.intersection(setB).sorted())
      #expect(Array(a.symmetricDifference(b)) == setA.symmetricDifference(setB).sorted())
      #expect(a.count == setA.count)
      #expect(a == IndexSet(setA.sorted()))
    }
  }

  @Test
  func sparseSetsBuildInLinearTime() {
    let started = Date()
    let evens = IndexSet(stride(from: 0, to: 40_000, by: 2))
    #expect(evens.count == 20_000)
    var inserted = IndexSet()
    for value in stride(from: 39_998, through: 0, by: -2) { inserted.insert(value) }
    #expect(inserted == evens)
    for value in stride(from: 1, to: 40_000, by: 2) { inserted.insert(value) }
    #expect(inserted == IndexSet(integersIn: 0 ..< 40_000))
    inserted.remove(500)
    #expect(Array(inserted.prefix(3)) == [0, 1, 2] && !inserted.contains(500) && inserted.count == 39_999)
    #expect(Date().timeIntervalSince(started) < 10)
  }

  @Test
  func movingKeepsOnlyOffsetsInsideTheCollection() {
    var items = ["a", "b", "c", "d"]
    items.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)
    #expect(items == ["b", "d", "a", "c"])
    var more = ["a", "b", "c"]
    more.move(fromOffsets: IndexSet(integersIn: 1...), toOffset: 0)
    #expect(more == ["b", "c", "a"])
    var set = IndexSet()
    #expect(!set.insert(Int.max).inserted)
    #expect(set.update(with: 4) == nil)
    #expect(set.update(with: 4) == 4)
  }
}
