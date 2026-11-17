import Testing
@_spi(Renderer) import SwiftUIWebFiber
@testable import SwiftUIWebFiber

/// The error an arena edit throws, or nil when it succeeds.
private func failure(_ edit: () throws -> Void) -> StructuralArenaError? {
  do { try edit(); return nil } catch { return error as? StructuralArenaError }
}

/// A live node's children, or nil when the handle is stale.
private func kids(_ arena: StructuralArena, _ id: StructuralNodeID) -> [StructuralNodeID]? {
  try? arena.children(of: id)
}

@Suite(.serialized)
struct StructuralArenaTests {
  @Test
  func generationsAndIndependentArenas() {
    let (a, b) = (StructuralArena(), StructuralArena())
    let x = a.allocate()
    let y = b.allocate()
    _expectTrue(a.release(x))
    let z = a.allocate()
    _expectNotEqual(x, z)
    _expectEqual(x.index, z.index)
    _expectEqual(z.generation, x.generation + 1)
    _expectFalse(a.isLive(x))
    _expectTrue(b.isLive(y))
    _expectFalse(a.release(x), "a stale release is idempotent, not a second free")
    _expectEqual(a.liveCount, 1)
  }

  @Test
  func topologyEditsAreAtomicAndReparent() throws {
    let a = StructuralArena()
    let (p, q, c) = (a.allocate(), a.allocate(), a.allocate())
    try a.setChildren(of: p, to: [q, c])
    _expectEqual(failure { try a.setChildren(of: q, to: [p]) }, .invalid)
    _expectEqual(failure { try a.setChildren(of: p, to: [c, c]) }, .invalid)
    _expectEqual(kids(a, p), [q, c])
    try a.setChildren(of: q, to: [c])
    _expectEqual(kids(a, p), [q])
    a.release(q)
    _expectTrue(a.isLive(c))
    _expectEqual(kids(a, p), [])
  }

  @Test
  func settingChildrenReusesTheParentsBuffer() throws {
    let a = StructuralArena()
    let (parent, child) = (a.allocate(), a.allocate())
    try a.setChildren(of: parent, to: [child])
    let pointer = kids(a, parent)?.withUnsafeBufferPointer { $0.baseAddress }
    let capacity = a.slots[Int(parent.index)].children.capacity
    try a.setChildren(of: parent, to: [child])
    _expectTrue(kids(a, parent)?.withUnsafeBufferPointer { $0.baseAddress } == pointer)
    _expectEqual(a.slots[Int(parent.index)].children.capacity, capacity)
  }

  @Test
  func synchronizationAndDynamicCapacity() throws {
    let a = StructuralArena()
    let ids = (0..<20_000).map { _ in a.allocate() }
    _expectEqual(a.liveCount, 20_000)
    try a.synchronize(liveIDs: Array(ids[..<3]))
    _expectEqual(a.liveCount, 3)
    try a.synchronize(liveIDs: [])
    _expectEqual(a.liveCount, 0)
    for _ in 0..<1000 { a.release(a.allocate()) }
    _expectEqual(a.liveCount, 0)
  }

  @Test
  func synchronizeIsIdempotentAndSurvivesAWrappedPassCounter() throws {
    let a = StructuralArena()
    let ids = (0..<8).map { _ in a.allocate() }
    try a.setChildren(of: ids[0], to: Array(ids[1..<4]))
    try a.synchronize(liveIDs: ids)
    try a.synchronize(liveIDs: ids)
    _expectEqual(a.liveCount, 8)
    _expectEqual(kids(a, ids[0]), Array(ids[1..<4]))
    // The pass counter wraps without retiring or keeping the wrong slots.
    a.pass = UInt32.max - 1
    for _ in 0..<2 {
      try a.synchronize(liveIDs: Array(ids[..<5]))
      _expectEqual(a.liveCount, 5)
    }
    try a.synchronize(liveIDs: Array(ids[..<2]))
    _expectEqual(a.liveCount, 2)
    _expectTrue(ids[2...].allSatisfy { !a.isLive($0) })
    // A reallocated slot is a new record and is retired like any other.
    let fresh = a.allocate()
    try a.synchronize(liveIDs: Array(ids[..<2]))
    _expectFalse(a.isLive(fresh))
    _expectEqual(a.liveCount, 2)
  }

  @Test
  func aStaleHandleInTheLiveListRetiresNothing() {
    let a = StructuralArena()
    let (keep, extra, stale) = (a.allocate(), a.allocate(), a.allocate())
    a.release(stale)
    _expectEqual(failure { try a.synchronize(liveIDs: [keep, stale]) }, .stale)
    _expectTrue(a.isLive(extra))
    _expectEqual(a.liveCount, 2)
  }

  @Test
  func duplicateAndCyclicChildrenAreRejectedAtEverySize() throws {
    let a = StructuralArena()
    let (root, mid) = (a.allocate(), a.allocate())
    try a.setChildren(of: root, to: [mid])
    let many = (0..<20).map { _ in a.allocate() }
    _expectEqual(failure { try a.setChildren(of: mid, to: many + [many[3]]) }, .invalid)
    _expectEqual(failure { try a.setChildren(of: mid, to: many + [root]) }, .invalid)
    _expectEqual(failure { try a.setChildren(of: mid, to: [many[0], many[0]]) }, .invalid)
    _expectEqual(failure { try a.setChildren(of: mid, to: [many[0], root]) }, .invalid)
    _expectEqual(failure { try a.setChildren(of: mid, to: [mid]) }, .invalid)
    _expectEqual(kids(a, mid), [])
    try a.setChildren(of: mid, to: many)
    _expectEqual(kids(a, mid), many)
  }

  @Test
  func generationExhaustionDoesNotAlias() {
    let a = StructuralArena()
    let id = a.allocate()
    a.slots[Int(id.index)].generation = .max
    let last = StructuralNodeID(index: id.index, generation: .max)
    _expectTrue(a.release(last))
    let next = a.allocate()
    _expectNotEqual(next.index, last.index)
    _expectFalse(a.isLive(last))
  }

  @Test
  func staleHandlesAreRejectedByEveryTopologyEntryPoint() throws {
    let a = StructuralArena()
    let (parent, child) = (a.allocate(), a.allocate())
    a.release(child)
    _expectEqual(failure { _ = try a.children(of: child) }, .stale)
    _expectEqual(failure { try a.setChildren(of: child, to: []) }, .stale)
    _expectEqual(failure { try a.setChildren(of: parent, to: [child]) }, .stale)
    _expectEqual(failure { try a.synchronize(liveIDs: [child]) }, .stale)
    try a.synchronize(liveIDs: [parent])
    _expectEqual(kids(a, parent), [])
  }

  @Test
  func releaseIgnoresADetachedStaleChildRecord() throws {
    let a = StructuralArena()
    let (parent, child) = (a.allocate(), a.allocate())
    try a.setChildren(of: parent, to: [child])
    // Only an interrupted host edit can leave a dead child in the list. Releasing the parent must still retire
    // safely and must not resurrect or write to that child.
    a.slots[Int(child.index)].live = false
    _expectTrue(a.release(parent))
    _expectEqual(a.liveCount, 1)
    _expectFalse(a.isLive(parent))
  }

  @Test
  func releaseIgnoresAStaleParentRecord() throws {
    let a = StructuralArena()
    let (parent, child) = (a.allocate(), a.allocate())
    try a.setChildren(of: parent, to: [child])
    // A partially applied edit may leave the child's parent link after the parent was retired.
    a.slots[Int(parent.index)].live = false
    _expectTrue(a.release(child))
    _expectEqual(a.liveCount, 1)
    _expectFalse(a.isLive(child))
  }

  @Test
  func replacingChildrenDetachesStaleChildRecordsSafely() throws {
    let a = StructuralArena()
    let (parent, child) = (a.allocate(), a.allocate())
    try a.setChildren(of: parent, to: [child])
    a.slots[Int(child.index)].live = false
    try a.setChildren(of: parent, to: [])
    _expectEqual(kids(a, parent), [])
  }

  @Test
  func capacityAndLivenessQueriesTrackReuse() throws {
    let a = StructuralArena()
    _expectEqual(a.liveCount, 0)
    _expectEqual(a.capacity, 0)
    let (parent, child) = (a.allocate(), a.allocate())
    _expectEqual(a.liveCount, 2)
    _expectEqual(a.capacity, 2)
    _expectTrue(a.isLive(parent) && a.isLive(child))
    _expectFalse(a.isLive(StructuralNodeID(index: .max, generation: .max)))
    try a.setChildren(of: parent, to: [child])
    try a.setChildren(of: parent, to: [])
    _expectEqual(kids(a, parent), [])
    a.release(child)
    _expectEqual(a.liveCount, 1)
    let replacement = a.allocate()
    _expectNotEqual(replacement, child)
    _expectEqual(a.liveCount, 2)
    _expectEqual(a.capacity, 2, "a released slot is reused before the array grows")
  }

  @Test
  func roundTripKeepsOrderAndErrors() throws {
    let a = StructuralArena()
    let (parent, child, emptyParent) = (a.allocate(), a.allocate(), a.allocate())
    try a.setChildren(of: parent, to: [child])
    _expectEqual(kids(a, parent), [child])
    _expectEqual(kids(a, emptyParent), [])
    try a.synchronize(liveIDs: [parent, child, emptyParent])
    _expectEqual(failure { try a.setChildren(of: child, to: [parent]) }, .invalid)
    a.release(child)
    let replacement = a.allocate()
    _expectNotEqual(replacement, child)
    _expectFalse(a.isLive(child))
    _expectEqual(failure { try a.setChildren(of: parent, to: [child]) }, .stale)
  }

  @Test
  func packedNodeIDKeepsGenerationAboveIndexAndRoundTrips() {
    let id = StructuralNodeID(index: 0xDEAD_BEEF, generation: 7)
    _expectEqual(id.packed, (UInt64(7) << 32) | 0xDEAD_BEEF)
    _expectEqual(StructuralNodeID(packed: id.packed), id)
    _expectEqual(StructuralNodeID(packed: 0x0000_0003_0000_0002), StructuralNodeID(index: 2, generation: 3))
  }
}
