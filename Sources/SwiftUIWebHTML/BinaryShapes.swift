/// A subtree whose structure repeats (its tags, namespaces, attribute names and where its texts are), which the page can build
/// by cloning a template it holds and writing only the values that differ from the template's
/// (Documentation/Architecture/BINARY_PATCHES.md, "Shapes").
///
/// The encoder counts the skeletons of the subtrees it builds. When a skeleton has been met often enough, the publication
/// carries `DEFINE id` and the template (the subtree as it was then, without handles), and builds the subtrees of that skeleton
/// as `SHAPE id`, their handles and the values that differ. Every publication carries the definition, with the values the
/// shape was defined with, until the host acknowledges one: a host that applied only the newest of the publications it was
/// sent (it drops the others) ends with the same template whichever it applied, and a definition the host acknowledged is one
/// that every publication it may have applied carried.
package final class BinaryShapeTable {
  package let capacity: Int
  /// A subtree needs at least this many elements to be a shape.
  package let minimumElements: Int
  /// How many subtrees of a skeleton, counting those of earlier publications, make it worth defining.
  package let instancesBeforeDefinition: Int
  /// Changes when the table is emptied; the page drops its templates when it sees a new one.
  package private(set) var generation: UInt32 = 0
  /// The publication being encoded, for the least recently used ids.
  private(set) var tick: UInt64 = 0
  /// The epoch of the newest definition: a publication before the host acknowledges it carries definitions.
  private(set) var newestDefinition: UInt64 = 0
  private(set) var entries: [UInt64: Entry] = [:]
  private var owners: [Entry] = []

  /// What the table keeps of a skeleton.
  final class Entry {
    var seen = 0
    /// The id of the template in the page, or -1 while the skeleton is only counted.
    var id = -1
    /// The epoch of the first publication of the run of publications that carry the definition: a page that acknowledged it
    /// or a later one holds the template.
    var definedEpoch: UInt64 = 0
    var blueprint: Blueprint?
    var lastTick: UInt64 = 0
  }

  /// The subtree a shape was defined with: its words, without handles, with the strings it carries (an index at or above the
  /// atom count names one of `strings`).
  struct Blueprint {
    var words: [UInt32]
    var strings: [[UInt8]]
  }

  package init(capacity: Int = 1024, minimumElements: Int = 3, instancesBeforeDefinition: Int = 3) {
    self.capacity = capacity
    self.minimumElements = minimumElements
    self.instancesBeforeDefinition = instancesBeforeDefinition
  }

  /// The number of shapes the page may hold.
  package var definedCount: Int { owners.count }

  /// Forgets everything and tells the page to do the same.
  package func reset() {
    entries.removeAll()
    owners.removeAll()
    newestDefinition = 0
    generation &+= 1
  }

  func noteDefinition(_ epoch: UInt64) { newestDefinition = max(newestDefinition, epoch) }

  /// The shapes the host may not hold yet, in the order of their ids.
  func pending(acked: UInt64) -> [Entry] {
    guard newestDefinition > acked else { return [] }
    return owners.filter { $0.blueprint != nil && $0.definedEpoch > acked }
  }

  func beginPublication() { tick &+= 1 }

  /// Counts a sighting of `key`.
  func touch(_ key: UInt64) {
    if let entry = entries[key] {
      entry.seen += 1
      return
    }
    // Skeletons that were only counted are not worth more than the shapes: when they pile up, they go.
    if entries.count > capacity * 8 {
      entries = entries.filter { $0.value.id >= 0 }
    }
    let entry = Entry()
    entry.seen = 1
    entries[key] = entry
  }

  /// Gives `entry` the id of a free place, or of the shape used least recently (not in this publication).
  func allocate(_ entry: Entry) -> Bool {
    if owners.count < capacity {
      entry.id = owners.count
      owners.append(entry)
      return true
    }
    var victim = -1
    var oldest = UInt64.max
    for (index, owner) in owners.enumerated() where owner.lastTick != tick && owner.lastTick < oldest {
      oldest = owner.lastTick
      victim = index
    }
    guard victim >= 0 else { return false }
    let evicted = owners[victim]
    evicted.id = -1
    evicted.blueprint = nil
    evicted.definedEpoch = 0
    entry.id = victim
    owners[victim] = entry
    return true
  }

  func forget(_ key: UInt64) {
    guard let entry = entries[key] else { return }
    if entry.id >= 0 && entry.id < owners.count && owners[entry.id] === entry {
      // The id stays with the page's template; nothing refers to it again until another skeleton takes it over.
      entry.lastTick = 0
    }
    entry.id = -1
    entry.blueprint = nil
    entry.definedEpoch = 0
    entry.seen = 0
  }
}

/// A subtree that was built in full and that a shape may stand for: its skeleton, where its words are, and the subtrees below it
/// that a shape may stand for.
struct BinaryShapePotential {
  var key: UInt64
  var start: Int
  var end: Int
  var children: [BinaryShapePotential]
}

/// A subtree a shape stands for.
struct BinaryShapeCandidate {
  var key: UInt64
  var start: Int
  var end: Int
}

/// Builds subtrees as `SHAPE` nodes in the words of a publication, and writes the definitions the host may lack.
struct BinaryShapeAssembler {
  let strings: BinaryStrings
  let table: BinaryShapeTable
  let covered: UInt64
  let acked: UInt64
  private(set) var definitions = 0
  private(set) var instances = 0

  init(strings: BinaryStrings, table: BinaryShapeTable, covered: UInt64, acked: UInt64) {
    self.strings = strings
    self.table = table
    self.covered = covered
    self.acked = acked
  }

  private var atomCount: UInt32 { UInt32(strings.atomCount) }

  /// The layout of a node's words: where its tag, its attribute count and its attributes are. An element is its op, its
  /// handle (index, generation, descriptor), the namespace of an `ELEMENT_NS`, its tag, the count and the pairs.
  private static func countOffset(_ op: UInt32) -> Int { op == _BinaryFormat.opElementNs ? 6 : 5 }

  /// The subtrees to build as shapes: of each region of the tree, the outermost subtree whose skeleton has been met often enough
  /// or that the host holds already.
  private func choose(_ roots: [BinaryShapePotential]) -> [BinaryShapeCandidate] {
    var chosen: [BinaryShapeCandidate] = []
    var stack: [BinaryShapePotential] = []
    stack.append(contentsOf: roots.reversed())
    while let node = stack.popLast() {
      if let entry = table.entries[node.key], entry.id >= 0 || entry.seen >= table.instancesBeforeDefinition {
        chosen.append(BinaryShapeCandidate(key: node.key, start: node.start, end: node.end))
      } else {
        stack.append(contentsOf: node.children.reversed())
      }
    }
    return chosen
  }

  /// `words` with the subtrees of `roots` built as shapes, and the definitions the host may lack at `defineAt`.
  mutating func assemble(_ words: [UInt32], _ roots: [BinaryShapePotential], defineAt: Int) -> [UInt32] {
    var chosen = choose(roots)
    chosen.sort(by: { $0.start < $1.start })
    // The shapes this publication uses are not for another skeleton to take over.
    for candidate in chosen { if let entry = table.entries[candidate.key], entry.id >= 0 { entry.lastTick = table.tick } }
    // A shape that is new is defined by the first of its subtrees.
    var defining: [UInt64: Int] = [:]
    for candidate in chosen {
      guard let entry = table.entries[candidate.key], entry.id < 0 else { continue }
      guard table.allocate(entry), let blueprint = makeBlueprint(words, candidate) else { table.forget(candidate.key); continue }
      entry.blueprint = blueprint
      entry.definedEpoch = covered
      entry.lastTick = table.tick
      table.noteDefinition(covered)
      definitions += 1
      defining[candidate.key] = candidate.start
    }
    var replaced: [(start: Int, end: Int, words: [UInt32])] = []
    for candidate in chosen {
      guard let entry = table.entries[candidate.key], entry.id >= 0, let blueprint = entry.blueprint else { continue }
      guard let shape = shapeWords(words, candidate, blueprint, same: defining[candidate.key] == candidate.start) else { table.forget(candidate.key); continue }
      replaced.append((candidate.start, candidate.end, shape))
    }
    var out: [UInt32] = []
    out.reserveCapacity(words.count)
    out.append(contentsOf: words[0..<defineAt])
    for entry in table.pending(acked: acked) { if let blueprint = entry.blueprint { writeDefinition(entry, blueprint, into: &out) } }
    var cursor = defineAt
    for replacement in replaced {
      out.append(contentsOf: words[cursor..<replacement.start])
      out.append(contentsOf: replacement.words)
      instances += 1
      cursor = replacement.end
    }
    out.append(contentsOf: words[cursor...])
    return out
  }

  /// The subtree as a template: its words with the handles zeroed and the strings it carries copied.
  private func makeBlueprint(_ words: [UInt32], _ candidate: BinaryShapeCandidate) -> BinaryShapeTable.Blueprint? {
    var copy: [UInt32] = []
    copy.reserveCapacity(candidate.end - candidate.start)
    var local: [UInt32: UInt32] = [:]
    var carried: [[UInt8]] = []
    func reference(_ index: UInt32) -> UInt32 {
      if index < atomCount { return index }
      if let known = local[index] { return known }
      let mapped = atomCount + UInt32(carried.count)
      carried.append(strings.ownBytes(at: index))
      local[index] = mapped
      return mapped
    }
    var position = candidate.start
    while position < candidate.end {
      let op = words[position]
      switch op {
      case _BinaryFormat.opElement, _BinaryFormat.opElementNs:
        let namespaced = op == _BinaryFormat.opElementNs
        let countAt = position + Self.countOffset(op)
        guard countAt < candidate.end else { return nil }
        let count = Int(words[countAt])
        copy.append(op)
        copy.append(0)
        copy.append(0)
        copy.append(0)
        if namespaced { copy.append(words[position + 4]) }
        copy.append(reference(words[countAt - 1]))
        copy.append(UInt32(count))
        var pair = 0
        while pair < count {
          copy.append(reference(words[countAt + 1 + pair * 2]))
          copy.append(reference(words[countAt + 2 + pair * 2]))
          pair += 1
        }
        position = countAt + 1 + count * 2
      case _BinaryFormat.opText:
        copy.append(op)
        copy.append(reference(words[position + 1]))
        position += 2
      case _BinaryFormat.opEnd:
        copy.append(op)
        position += 1
      default:
        return nil
      }
    }
    return BinaryShapeTable.Blueprint(words: copy, strings: carried)
  }

  /// `SHAPE id`, the handles of the subtree's elements in order and the values that differ from the template's, by their place
  /// among the values of the subtree (attribute values and texts, in order).
  private func shapeWords(_ words: [UInt32], _ candidate: BinaryShapeCandidate, _ blueprint: BinaryShapeTable.Blueprint, same: Bool) -> [UInt32]? {
    guard let entry = table.entries[candidate.key] else { return nil }
    var handles: [UInt32] = []
    var fills: [UInt32] = []
    var slot: UInt32 = 0
    var position = candidate.start
    var template = 0
    while position < candidate.end {
      guard template < blueprint.words.count else { return nil }
      let op = words[position]
      guard op == blueprint.words[template] else { return nil }
      switch op {
      case _BinaryFormat.opElement, _BinaryFormat.opElementNs:
        let offset = Self.countOffset(op)
        let count = Int(words[position + offset])
        guard Int(blueprint.words[template + offset]) == count else { return nil }
        handles.append(words[position + 1])
        handles.append(words[position + 2])
        handles.append(words[position + 3])
        var pair = 0
        while pair < count {
          let value = words[position + offset + 2 + pair * 2]
          if !same && !equal(value, blueprint.words[template + offset + 2 + pair * 2], blueprint) {
            fills.append(slot)
            fills.append(value)
          }
          slot += 1
          pair += 1
        }
        position += offset + 1 + count * 2
        template += offset + 1 + count * 2
      case _BinaryFormat.opText:
        let value = words[position + 1]
        if !same && !equal(value, blueprint.words[template + 1], blueprint) {
          fills.append(slot)
          fills.append(value)
        }
        slot += 1
        position += 2
        template += 2
      default:
        position += 1
        template += 1
      }
    }
    guard template == blueprint.words.count else { return nil }
    var out: [UInt32] = [_BinaryFormat.opShape, UInt32(entry.id), UInt32(handles.count / 3)]
    out.append(contentsOf: handles)
    out.append(UInt32(fills.count / 2))
    out.append(contentsOf: fills)
    return out
  }

  /// Whether the string `current` of this publication is the string `held` of a blueprint.
  private func equal(_ current: UInt32, _ held: UInt32, _ blueprint: BinaryShapeTable.Blueprint) -> Bool {
    let currentIsAtom = current < atomCount, heldIsAtom = held < atomCount
    if currentIsAtom || heldIsAtom { return currentIsAtom && heldIsAtom && current == held }
    return strings.ownEquals(current, blueprint.strings[Int(held - atomCount)])
  }

  /// `DEFINE id` and the template, with its strings in this publication.
  private func writeDefinition(_ entry: BinaryShapeTable.Entry, _ blueprint: BinaryShapeTable.Blueprint, into out: inout [UInt32]) {
    out.append(_BinaryFormat.opDefine)
    out.append(UInt32(entry.id))
    var mapped = [UInt32?](repeating: nil, count: blueprint.strings.count)
    func reference(_ index: UInt32) -> UInt32 {
      if index < atomCount { return index }
      let local = Int(index - atomCount)
      if let known = mapped[local] { return known }
      let made = strings.internBytes(blueprint.strings[local])
      mapped[local] = made
      return made
    }
    var position = 0
    let words = blueprint.words
    while position < words.count {
      let op = words[position]
      switch op {
      case _BinaryFormat.opElement, _BinaryFormat.opElementNs:
        let offset = Self.countOffset(op)
        let count = Int(words[position + offset])
        out.append(contentsOf: words[position..<(position + offset - 1)])
        out.append(reference(words[position + offset - 1]))
        out.append(UInt32(count))
        var pair = 0
        while pair < count {
          out.append(reference(words[position + offset + 1 + pair * 2]))
          out.append(reference(words[position + offset + 2 + pair * 2]))
          pair += 1
        }
        position += offset + 1 + count * 2
      case _BinaryFormat.opText:
        out.append(op)
        out.append(reference(words[position + 1]))
        position += 2
      default:
        out.append(op)
        position += 1
      }
    }
  }
}
