/// Why the arena refused an edit. Nothing is modified when one is thrown.
enum StructuralArenaError: Error {
  /// A handle is not live: it was released, or its slot was reused.
  case stale
  /// The edit would give a node two parents, list a child twice, or make a node its own ancestor.
  case invalid
}

/// Generational storage for the Fiber tree's structure. A handle is local to its arena: the slot index plus the
/// slot's generation, which is bumped on release so a stale callback never reaches a recycled node. Slots are one
/// contiguous array and indices stand in for references; nothing is allocated per node but its child list.
final class StructuralArena {
  struct Slot {
    /// Starts at 1, so a handle is never all zero.
    var generation: UInt32 = 1
    var live = false
    /// The pass that last stamped this slot; see `nextPass`.
    var mark: UInt32 = 0
    var parent: StructuralNodeID?
    var children: [StructuralNodeID] = []
  }

  var slots: [Slot] = []
  private var free: [UInt32] = []
  private(set) var liveCount = 0
  var pass: UInt32 = 0
  var capacity: Int { slots.count }

  func isLive(_ id: StructuralNodeID) -> Bool {
    let index = Int(id.index)
    return index < slots.count && slots[index].live && slots[index].generation == id.generation
  }

  func allocate() -> StructuralNodeID {
    let index: UInt32
    if let reused = free.popLast() {
      index = reused
    } else {
      index = UInt32(slots.count)
      slots.append(Slot())
    }
    slots[Int(index)].live = true
    liveCount += 1
    return StructuralNodeID(index: index, generation: slots[Int(index)].generation)
  }

  /// Retires one record and returns false when `id` is already stale. Children are detached, not destroyed; the
  /// renderer explicitly disposes complete subtrees in lifecycle order.
  @discardableResult
  func release(_ id: StructuralNodeID) -> Bool {
    guard isLive(id) else { return false }
    let index = Int(id.index)
    if let parent = slots[index].parent, isLive(parent) {
      slots[Int(parent.index)].children.removeAll { $0 == id }
    }
    for child in slots[index].children where isLive(child) { slots[Int(child.index)].parent = nil }
    slots[index].children = []
    slots[index].live = false
    slots[index].parent = nil
    // Never wrap a generation and resurrect an old event token. An exhausted slot is retired permanently;
    // later allocations grow the array.
    if slots[index].generation != .max {
      slots[index].generation += 1
      free.append(UInt32(index))
    }
    liveCount -= 1
    return true
  }

  func children(of parent: StructuralNodeID) throws(StructuralArenaError) -> [StructuralNodeID] {
    guard isLive(parent) else { throw .stale }
    return slots[Int(parent.index)].children
  }

  /// Replaces `parent`'s children, moving any that sit under another parent. The whole edit is validated before
  /// the topology changes. Ancestors are stamped with one pass and the children with the next, so the cycle and
  /// duplicate checks are linear and allocate nothing.
  func setChildren(of parent: StructuralNodeID, to children: [StructuralNodeID]) throws(StructuralArenaError) {
    guard isLive(parent) else { throw .stale }
    let ancestors = nextPass(2)
    var ancestor: StructuralNodeID? = parent
    while let id = ancestor {
      slots[Int(id.index)].mark = ancestors
      ancestor = slots[Int(id.index)].parent
    }
    for child in children {
      guard isLive(child) else { throw .stale }
      if slots[Int(child.index)].mark == ancestors { throw .invalid }
    }
    for child in children {
      if slots[Int(child.index)].mark == ancestors + 1 { throw .invalid }
      slots[Int(child.index)].mark = ancestors + 1
    }
    // Reuse the parent's child buffer: it is taken out of the slot while the other slots are edited.
    var buffer: [StructuralNodeID] = []
    swap(&buffer, &slots[Int(parent.index)].children)
    for old in buffer where isLive(old) { slots[Int(old.index)].parent = nil }
    buffer.removeAll(keepingCapacity: true)
    buffer.append(contentsOf: children)
    for child in children {
      if let previous = slots[Int(child.index)].parent {
        slots[Int(previous.index)].children.removeAll { $0 == child }
      }
      slots[Int(child.index)].parent = parent
    }
    swap(&buffer, &slots[Int(parent.index)].children)
  }

  /// Retires every live record that `liveIDs` does not list; nothing is retired when it names a stale handle.
  /// Listed slots are stamped with the pass number and the slots scanned once, so no set is built per pass.
  func synchronize(liveIDs: [StructuralNodeID]) throws(StructuralArenaError) {
    for id in liveIDs where !isLive(id) { throw .stale }
    let pass = nextPass()
    for id in liveIDs { slots[Int(id.index)].mark = pass }
    for index in slots.indices where slots[index].live && slots[index].mark != pass {
      release(StructuralNodeID(index: UInt32(index), generation: slots[index].generation))
    }
  }

  /// The first of `count` fresh values for `Slot.mark`. When the counter would wrap, every mark is cleared first
  /// so a stale one cannot match.
  private func nextPass(_ count: UInt32 = 1) -> UInt32 {
    if pass > UInt32.max - count {
      for index in slots.indices { slots[index].mark = 0 }
      pass = 0
    }
    pass += count
    return pass - count + 1
  }
}
