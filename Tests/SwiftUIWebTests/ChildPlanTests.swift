import Testing
@testable import SwiftUIWebFiber

@Suite(.serialized)
struct ChildPlanTests {
  private let insert = ChildPlan.insert

  @Test
  func insertsMovesAndRemovals() {
    let moved = ChildPlan(old: [1, 2, 3], new: [3, 4, 1])
    _expectEqual(moved.oldIndices, [2, insert, 0])
    _expectEqual(moved.removals, [1])
    let first = ChildPlan(old: [Int](), new: [1])
    _expectEqual(first.oldIndices, [insert])
    _expectEqual(first.removals, [])
    let cleared = ChildPlan(old: [1], new: [Int]())
    _expectEqual(cleared.oldIndices, [])
    _expectEqual(cleared.removals, [0])
  }

  @Test
  func duplicateIDsNeverReuseOneRecordTwice() {
    let plan = ChildPlan(old: [7, 7, 8], new: [7, 7])
    _expectEqual(plan.oldIndices, [0, insert])
    _expectEqual(plan.removals, [1, 2])
    let same = ChildPlan(old: [7, 7], new: [7, 7])
    _expectEqual(same.oldIndices, [0, insert])
    _expectEqual(same.removals, [1])
  }

  @Test
  func aKeptRecordKeepsItsOldIndexNextToAnInsertion() {
    let plan = ChildPlan(old: [1, 2], new: [2, 3])
    _expectEqual(plan.oldIndices[0], 1)
    _expectEqual(plan.removals.count, 1)
  }

  @Test
  func deterministicRandomizedContract() {
    var seed: UInt64 = 0x51f17e
    func next() -> Int {
      seed = seed &* 6364136223846793005 &+ 1
      return Int((seed >> 32) % 70)
    }
    for _ in 0..<2000 {
      let old = (0..<50).map { _ in next() }
      let new = (0..<60).map { _ in next() }
      let plan = ChildPlan(old: old, new: new)
      var seen = [Bool](repeating: false, count: old.count)
      for (newIndex, oldIndex) in plan.oldIndices.enumerated() where oldIndex != insert {
        _expectFalse(seen[Int(oldIndex)])
        seen[Int(oldIndex)] = true
        _expectEqual(old[Int(oldIndex)], new[newIndex])
      }
      for index in plan.removals {
        _expectFalse(seen[Int(index)])
        seen[Int(index)] = true
      }
      _expectTrue(seen.allSatisfy { $0 })
    }
  }
}
