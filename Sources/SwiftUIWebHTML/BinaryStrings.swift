/// The atoms of the binary publication format as a table of open addressing over FNV hashes: built once, never changed
/// after it is built, and so shared by every publication. Lookups work on bytes, so no `String` is made to find an
/// index (the name of an attribute arrives as bytes of the attribute sorter's arena, a value as bytes of the scratch it
/// was assembled in).
package final class BinaryAtomTable: @unchecked Sendable {
  static let shared = BinaryAtomTable()

  let count = Int(_BinaryFormat.atomCount)
  private var slots: [Int32]
  private let mask: Int
  private var hashes: [UInt32] = []
  private var starts: [Int32] = []
  private var lengths: [Int32] = []
  private var arena: [UInt8] = []

  #if SWIFTUIWEB_RELEASE
  /// Where a release reads the atoms: the page's host holds the same table (Tools/binary-atoms.generated.js) and writes it,
  /// NUL-separated, into the buffer it is given, returning its length (so a call with no room asks how much it needs).
  /// The browser launch installs it before the first publication; a release app.wasm does not carry the atoms itself.
  nonisolated(unsafe) package static var hostAtoms: ((UnsafeMutablePointer<UInt8>?, Int) -> Int)?
  #endif

  private init() {
    var capacity = 1024
    while capacity < count * 3 { capacity *= 2 }
    slots = [Int32](repeating: -1, count: capacity)
    mask = capacity - 1
    hashes.reserveCapacity(count)
    starts.reserveCapacity(count)
    lengths.reserveCapacity(count)
    // The atoms are one NUL-separated string.
    #if SWIFTUIWEB_RELEASE
    guard let host = Self.hostAtoms, case let length = host(nil, 0), length > 0 else { fatalError("no host binary atoms") }
    var atoms = [UInt8](repeating: 0, count: length)
    guard atoms.withUnsafeMutableBufferPointer({ host($0.baseAddress, $0.count) }) == atoms.count else { fatalError("host binary atoms changed") }
    atoms.withUnsafeBufferPointer { add($0.baseAddress!, total: $0.count) }
    #else
    let atoms = _BinaryFormat.atoms
    add(atoms.utf8Start, total: atoms.utf8CodeUnitCount)
    #endif
    if hashes.count != count { fatalError("binary atoms differ") }
  }

  /// Indexes the NUL-separated atoms at `bytes`.
  private func add(_ bytes: UnsafePointer<UInt8>, total: Int) {
    arena.reserveCapacity(total)
    var begin = 0
    var index = 0
    while index <= total {
      if index == total || bytes[index] == 0 {
        let hash = Self.hash(bytes + begin, count: index - begin)
        var slot = Int(hash & UInt32(truncatingIfNeeded: mask))
        while slots[slot] >= 0 { slot = (slot + 1) & mask }
        slots[slot] = Int32(hashes.count)
        hashes.append(hash)
        starts.append(Int32(arena.count))
        lengths.append(Int32(index - begin))
        arena.append(contentsOf: UnsafeBufferPointer(start: bytes + begin, count: index - begin))
        begin = index + 1
      }
      index += 1
    }
  }

  /// The index of the atom spelled `text`, which must be one.
  func index(of text: StaticString) -> UInt32 {
    let bytes = text.utf8Start
    let count = text.utf8CodeUnitCount
    return index(bytes, count: count, hash: Self.hash(bytes, count: count)) ?? UInt32.max
  }

  /// The index of the atom made of these bytes, if there is one.
  func index(_ bytes: UnsafePointer<UInt8>, count length: Int, hash: UInt32) -> UInt32? {
    var slot = Int(hash & UInt32(truncatingIfNeeded: mask))
    while true {
      let entry = slots[slot]
      if entry < 0 { return nil }
      let index = Int(entry)
      if hashes[index] == hash, Int(lengths[index]) == length, matches(index, bytes, count: length) { return UInt32(index) }
      slot = (slot + 1) & mask
    }
  }

  private func matches(_ index: Int, _ bytes: UnsafePointer<UInt8>, count length: Int) -> Bool {
    arena.withUnsafeBufferPointer { arena in BinaryAtomTable.equal(arena.baseAddress! + Int(starts[index]), bytes, count: length) }
  }

  /// A multiplicative hash that takes the bytes eight at a time. Nothing outside this process depends on it: strings travel
  /// as indices. Zero is kept for "not in a table", so a string that hashes to it is given another hash.
  @inline(__always)
  static func hash(_ bytes: UnsafePointer<UInt8>, count: Int) -> UInt32 {
    // Seeded per run like `BinaryHash`: strings chosen to share a probe sequence would make interning quadratic.
    var hash = (UInt64(truncatingIfNeeded: count) ^ BinaryHash.seed) &* 0x9E37_79B9_7F4A_7C15
    let raw = UnsafeRawPointer(bytes)
    var offset = 0
    while offset &+ 8 <= count {
      hash = (hash ^ raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) &* 0xFF51_AFD7_ED55_8CCD
      hash ^= hash >> 32
      offset &+= 8
    }
    if offset < count {
      var tail: UInt64 = 0
      var shift: UInt64 = 0
      while offset < count {
        tail |= UInt64(bytes[offset]) << shift
        shift &+= 8
        offset &+= 1
      }
      hash = (hash ^ tail) &* 0xFF51_AFD7_ED55_8CCD
      hash ^= hash >> 32
    }
    let folded = UInt32(truncatingIfNeeded: hash ^ (hash >> 29))
    return folded == 0 ? 1 : folded
  }

  /// Whether the `count` bytes at `a` and `b` are the same, compared eight at a time.
  @inline(__always)
  static func equal(_ a: UnsafePointer<UInt8>, _ b: UnsafePointer<UInt8>, count: Int) -> Bool {
    let first = UnsafeRawPointer(a), second = UnsafeRawPointer(b)
    var offset = 0
    while offset &+ 8 <= count {
      if first.loadUnaligned(fromByteOffset: offset, as: UInt64.self) != second.loadUnaligned(fromByteOffset: offset, as: UInt64.self) { return false }
      offset &+= 8
    }
    while offset < count {
      if a[offset] != b[offset] { return false }
      offset &+= 1
    }
    return true
  }
}

/// The strings of one binary publication (Documentation/Architecture/BINARY_PATCHES.md, "Format"). The first
/// `_BinaryFormat.atomCount` indices name the atoms every build knows (tags, attribute names, frequent values); the ones
/// after them name this publication's own strings, which the page decodes once. A short own string is looked up before it
/// is added, because class lists and style texts repeat a lot; a longer one (a path, a data URL) is added as it comes.
final class BinaryStrings {
  /// Own strings up to this many bytes are looked up before they are appended.
  static let internLimit = 64

  private let atoms = BinaryAtomTable.shared
  private var slots: [Int32]
  private var mask: Int
  /// Per own string: its hash (zero when it is not in the table), where it starts in `arena`, and its length.
  private var hashes: [UInt32] = []
  private var starts: [Int32] = []
  private var lengths: [Int32] = []
  /// The own strings, each after a NUL that separates it from the one before: the string section of the publication.
  private var arena: [UInt8] = []
  /// Own strings in the table (those added by `intern`).
  private var tableCount = 0

  init() {
    slots = [Int32](repeating: -1, count: 256)
    mask = 255
  }

  var ownCount: Int { hashes.count }

  /// The bytes of the own strings, NUL-separated.
  var ownBytes: [UInt8] { arena }

  /// The index of the string made of these bytes, added to the own strings when it is not an atom or there yet.
  func intern(_ bytes: UnsafePointer<UInt8>, count: Int) -> UInt32 {
    if count > Self.internLimit { return append(bytes, count: count, hash: 0) }
    let hash = BinaryAtomTable.hash(bytes, count: count)
    if let atom = atoms.index(bytes, count: count, hash: hash) { return atom }
    var slot = Int(hash & UInt32(truncatingIfNeeded: mask))
    while true {
      let entry = slots[slot]
      if entry < 0 { break }
      let index = Int(entry)
      if hashes[index] == hash, Int(lengths[index]) == count, matches(index, bytes, count: count) { return UInt32(atoms.count + index) }
      slot = (slot + 1) & mask
    }
    let index = append(bytes, count: count, hash: hash)
    slots[slot] = Int32(index) - Int32(atoms.count)
    tableCount += 1
    // Half full: grow, so the probes stay short.
    if tableCount * 2 > slots.count { rehash() }
    return index
  }

  /// Adds a string that is unique to its element (a node id, an event token) without looking it up: it would never be found.
  func appendUnique(_ bytes: UnsafePointer<UInt8>, count: Int) -> UInt32 { append(bytes, count: count, hash: 0) }

  /// The index of the atom made of these bytes, if there is one. Nothing is added.
  func atomIndex(_ bytes: UnsafePointer<UInt8>, count: Int) -> UInt32? {
    atoms.index(bytes, count: count, hash: BinaryAtomTable.hash(bytes, count: count))
  }

  /// What names a string from one publication to the next: its atom index, or the hash of its bytes.
  func identity(of index: UInt32) -> UInt64 {
    if Int(index) < atoms.count { return UInt64(index) }
    let local = Int(index) - atoms.count
    return arena.withUnsafeBufferPointer { arena in
      BinaryHash.mix(BinaryHash.seed ^ (1 << 40), arena.baseAddress! + Int(starts[local]), count: Int(lengths[local]))
    }
  }

  /// The bytes of one of this publication's own strings.
  func ownBytes(at index: UInt32) -> [UInt8] {
    let local = Int(index) - atoms.count
    let start = Int(starts[local])
    return Array(arena[start..<(start + Int(lengths[local]))])
  }

  /// Whether one of this publication's own strings is `bytes`.
  func ownEquals(_ index: UInt32, _ bytes: [UInt8]) -> Bool {
    let local = Int(index) - atoms.count
    guard Int(lengths[local]) == bytes.count else { return false }
    let start = Int(starts[local])
    var offset = 0
    while offset < bytes.count {
      if arena[start + offset] != bytes[offset] { return false }
      offset += 1
    }
    return true
  }

  /// The index of the string made of `bytes`, added when it is not an atom or there yet.
  func internBytes(_ bytes: [UInt8]) -> UInt32 {
    if bytes.isEmpty { return internEmpty() }
    return bytes.withUnsafeBufferPointer { intern($0.baseAddress!, count: $0.count) }
  }

  /// The number of atoms: an index below it is an atom.
  var atomCount: Int { atoms.count }

  /// The index of the empty string.
  func internEmpty() -> UInt32 {
    var zero: UInt8 = 0
    return withUnsafePointer(to: &zero) { intern($0, count: 0) }
  }

  /// Adds an own string and returns its index.
  private func append(_ bytes: UnsafePointer<UInt8>, count: Int, hash: UInt32) -> UInt32 {
    let index = hashes.count
    if index > 0 { arena.append(0) }
    starts.append(Int32(arena.count))
    arena.append(contentsOf: UnsafeBufferPointer(start: bytes, count: count))
    hashes.append(hash)
    lengths.append(Int32(count))
    return UInt32(atoms.count + index)
  }

  private func rehash() {
    let capacity = slots.count * 2
    slots = [Int32](repeating: -1, count: capacity)
    mask = capacity - 1
    for index in 0..<hashes.count where hashes[index] != 0 {
      var slot = Int(hashes[index] & UInt32(truncatingIfNeeded: mask))
      while slots[slot] >= 0 { slot = (slot + 1) & mask }
      slots[slot] = Int32(index)
    }
  }

  private func matches(_ index: Int, _ bytes: UnsafePointer<UInt8>, count: Int) -> Bool {
    arena.withUnsafeBufferPointer { arena in count == 0 || BinaryAtomTable.equal(arena.baseAddress! + Int(starts[index]), bytes, count: count) }
  }
}

/// The 64-bit hashes of the publisher's bookkeeping: of the attributes of an element, of its identity and of its list of
/// children. They are compared with the ones of the publication before, so only their consistency within a run matters.
enum BinaryHash {
  /// Random for each run: the hashes cover text from the page and from servers, and a fixed, public seed would let such
  /// text be chosen to collide, so a changed node would hash as unchanged and keep stale content.
  static let seed: UInt64 = {
    var generator = SystemRandomNumberGenerator()
    return generator.next() | 1
  }()

  /// Folds one word into a hash; the order of the words matters.
  @inline(__always)
  static func mix(_ hash: UInt64, _ word: UInt64) -> UInt64 {
    let mixed = (hash ^ word) &* 0x9E37_79B9_7F4A_7C15
    return mixed ^ (mixed >> 32)
  }

  /// Folds `count` bytes into a hash, eight at a time.
  @inline(__always)
  static func mix(_ hash: UInt64, _ bytes: UnsafePointer<UInt8>, count: Int) -> UInt64 {
    var hash = mix(hash, UInt64(truncatingIfNeeded: count))
    let raw = UnsafeRawPointer(bytes)
    var offset = 0
    while offset &+ 8 <= count {
      hash = mix(hash, raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
      offset &+= 8
    }
    if offset < count {
      var tail: UInt64 = 0
      var shift: UInt64 = 0
      while offset < count {
        tail |= UInt64(bytes[offset]) << shift
        shift &+= 8
        offset &+= 1
      }
      hash = mix(hash, tail)
    }
    return hash
  }

  static func mix(_ hash: UInt64, _ string: String) -> UInt64 {
    var result = hash
    if string.utf8.withContiguousStorageIfAvailable({ (buffer: UnsafeBufferPointer<UInt8>) -> Void in
      if let start = buffer.baseAddress { result = mix(hash, start, count: buffer.count) } else { result = mix(hash, 0) }
    }) != nil { return result }
    var owned = string
    owned.withUTF8 { buffer in
      if let start = buffer.baseAddress { result = mix(hash, start, count: buffer.count) } else { result = mix(hash, 0) }
    }
    return result
  }
}
