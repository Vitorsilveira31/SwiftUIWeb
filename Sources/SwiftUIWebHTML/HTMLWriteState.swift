import SwiftUIWebCore

/// A node whose children are being written: what its closing needs once they are.
struct HTMLWriteFrame {
  let node: _RenderNode
  let children: [_RenderNode]
  var next = 0
  let start: Int
  /// The bytes of the tag name, which sit at `start + 1`; -1 for a fragment, which writes no element of its own.
  let tagLength: Int
  /// An element written past `maxElementDepth`: already closed, so it adds no depth and writes nothing at its end.
  var flat = false
  let writesChildren: Bool

  var isElement: Bool { tagLength >= 0 }
}

enum HTMLAttributeValue: UInt8 {
  /// The node's attribute at `source`.
  case text
  /// `class`: the attribute at `source` (if any) and then the node's class list.
  case classes
  /// `style`: the attribute at `source` (if any) and then the node's declarations.
  case style
  /// A `data-fiber-event-*` attribute: the event name at `source` in `eventValues`.
  case event
}

/// One attribute of the node being written: where its name sits in the scratch arena, and what its value is.
struct HTMLAttributeItem {
  var keyStart: Int
  var keyLength: Int
  var kind: HTMLAttributeValue
  var source: Int
  /// A name with a non-ASCII byte is ordered as the `String` it is (canonical ordering is not bytewise).
  var nonASCII: Bool
}

/// Everything one serialization works in: the output bytes, the stack of open nodes, and the scratch a node's
/// attributes are sorted in. All of it is plain memory allocated once per serialization (the arena and the item list
/// grow only when a node has more attributes than any before it) and reused for every node, so writing a node
/// allocates nothing.
struct HTMLWriteState {
  var bytes: HTMLByteBuffer
  /// Elements that are open and still nest: what the parser's stack of open elements holds.
  var depth = 0

  private(set) var frames: UnsafeMutablePointer<HTMLWriteFrame>
  private(set) var frameCount = 0
  private var frameCapacity = 64

  private var arena: UnsafeMutablePointer<UInt8>
  private var arenaCount = 0
  private var arenaCapacity = 1024
  private(set) var items: UnsafeMutablePointer<HTMLAttributeItem>
  private(set) var itemCount = 0
  private var itemCapacity = 32
  var eventValues: [String] = []

  init(capacity: Int) {
    bytes = HTMLByteBuffer(capacity: capacity)
    frames = .allocate(capacity: frameCapacity)
    arena = .allocate(capacity: arenaCapacity)
    items = .allocate(capacity: itemCapacity)
  }

  mutating func release() {
    bytes.deallocate()
    frames.deinitialize(count: frameCount)
    frames.deallocate()
    arena.deallocate()
    items.deallocate()
  }

  // MARK: Open nodes

  mutating func pushFrame(_ frame: HTMLWriteFrame) {
    if frameCount == frameCapacity {
      let next = UnsafeMutablePointer<HTMLWriteFrame>.allocate(capacity: frameCapacity * 2)
      next.moveInitialize(from: frames, count: frameCount)
      frames.deallocate()
      frames = next
      frameCapacity *= 2
    }
    (frames + frameCount).initialize(to: frame)
    frameCount += 1
  }

  mutating func popFrame() -> HTMLWriteFrame {
    frameCount -= 1
    return (frames + frameCount).move()
  }

  // MARK: Attributes of the node being written

  mutating func resetAttributes() {
    arenaCount = 0
    itemCount = 0
    if !eventValues.isEmpty { eventValues.removeAll(keepingCapacity: true) }
  }

  @inline(__always)
  func keyBytes(_ item: HTMLAttributeItem) -> UnsafePointer<UInt8> { UnsafePointer(arena + item.keyStart) }

  private mutating func reserveArena(_ extra: Int) {
    guard arenaCount + extra > arenaCapacity else { return }
    let capacity = max(arenaCapacity * 2, arenaCount + extra)
    let next = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    next.initialize(from: arena, count: arenaCount)
    arena.deallocate()
    arena = next
    arenaCapacity = capacity
  }

  private mutating func append(_ item: HTMLAttributeItem) -> Int {
    if itemCount == itemCapacity {
      let next = UnsafeMutablePointer<HTMLAttributeItem>.allocate(capacity: itemCapacity * 2)
      next.moveInitialize(from: items, count: itemCount)
      items.deallocate()
      items = next
      itemCapacity *= 2
    }
    (items + itemCount).initialize(to: item)
    itemCount += 1
    return itemCount - 1
  }

  /// Adds an attribute named `key`, copying the name into the arena. Returns its place in the list.
  mutating func addItem(key: String, kind: HTMLAttributeValue, source: Int) -> Int {
    let start = arenaCount
    var high: UInt8 = 0
    if key.utf8.withContiguousStorageIfAvailable({ name in high = store(name) }) == nil {
      var owned = key
      owned.withUTF8 { name in high = store(name) }
    }
    return append(HTMLAttributeItem(keyStart: start, keyLength: arenaCount - start, kind: kind, source: source, nonASCII: high >= 0x80))
  }

  /// Copies a name onto the end of the arena. Returns its bytes ORed together, to tell whether any is not ASCII.
  private mutating func store(_ name: UnsafeBufferPointer<UInt8>) -> UInt8 {
    reserveArena(name.count)
    var high: UInt8 = 0
    var index = 0
    while index < name.count {
      let byte = name[index]
      high |= byte
      arena[arenaCount + index] = byte
      index += 1
    }
    arenaCount += name.count
    return high
  }

  /// Adds the attribute `data-fiber-event-<name>`, or returns the attribute of that name the node already has.
  mutating func addEventKey(name: String) -> Int {
    var name = name
    let start = arenaCount
    var high: UInt8 = 0
    let prefix: StaticString = "data-fiber-event-"
    name.withUTF8 { bytes in
      reserveArena(prefix.utf8CodeUnitCount + bytes.count)
      var index = 0
      while index < prefix.utf8CodeUnitCount { arena[start + index] = prefix.utf8Start[index]; index += 1 }
      var offset = 0
      while offset < bytes.count {
        let byte = bytes[offset]
        high |= byte
        arena[start + index + offset] = byte
        offset += 1
      }
      arenaCount = start + index + offset
    }
    let added = HTMLAttributeItem(keyStart: start, keyLength: arenaCount - start, kind: .event, source: 0, nonASCII: high >= 0x80)
    var candidate = 0
    while candidate < itemCount {
      if sameName(items[candidate], added) {
        arenaCount = start
        return candidate
      }
      candidate += 1
    }
    return append(added)
  }

  /// Whether two names are the same string (canonically equivalent strings are, whatever their bytes).
  private func sameName(_ a: HTMLAttributeItem, _ b: HTMLAttributeItem) -> Bool {
    if !a.nonASCII && !b.nonASCII {
      if a.keyLength != b.keyLength { return false }
      var index = 0
      while index < a.keyLength {
        if arena[a.keyStart + index] != arena[b.keyStart + index] { return false }
        index += 1
      }
      return true
    }
    return name(of: a) == name(of: b)
  }

  private func name(of item: HTMLAttributeItem) -> String {
    String(htmlUTF8: UnsafeBufferPointer(start: UnsafePointer(arena + item.keyStart), count: item.keyLength))
  }

  /// Whether `a`'s name sorts after `b`'s: bytewise for ASCII names, which is the order of `String`'s `>` on them.
  private func sortsAfter(_ a: HTMLAttributeItem, _ b: HTMLAttributeItem) -> Bool {
    if !a.nonASCII && !b.nonASCII {
      let shared = min(a.keyLength, b.keyLength)
      var index = 0
      while index < shared {
        let x = arena[a.keyStart + index], y = arena[b.keyStart + index]
        if x != y { return x > y }
        index += 1
      }
      return a.keyLength > b.keyLength
    }
    return name(of: a) > name(of: b)
  }

  /// A stable insertion sort by name: a node carries a handful of attributes, and the sort is the same for a few
  /// entries as the generic one but needs no buffer and no comparator closure.
  mutating func sortItems(_ range: Range<Int>) {
    var index = range.lowerBound + 1
    while index < range.upperBound {
      let item = items[index]
      var position = index
      while position > range.lowerBound && sortsAfter(items[position - 1], item) {
        items[position] = items[position - 1]
        position -= 1
      }
      items[position] = item
      index += 1
    }
  }
}
