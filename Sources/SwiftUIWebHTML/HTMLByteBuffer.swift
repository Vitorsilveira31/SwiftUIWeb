/// The bytes of one serialization: a buffer that grows by doubling and is written through its raw pointer, so appending
/// a fixed fragment, a run of text or an attribute name is a capacity check and a copy. There is no `String`, no
/// `Array` append and no per-node allocation on the path that writes HTML (`StaticHTMLFiberRenderer`).
///
/// The buffer is plain memory the owner releases (`deallocate()`): the pointer is stable only until the next append.
struct HTMLByteBuffer {
  private(set) var base: UnsafeMutablePointer<UInt8>
  private(set) var count = 0
  private var capacity: Int

  init(capacity: Int) {
    self.capacity = max(capacity, 64)
    base = .allocate(capacity: self.capacity)
  }

  func deallocate() { base.deallocate() }

  @inline(__always)
  mutating func reserve(_ extra: Int) {
    if count &+ extra > capacity { grow(toFit: count &+ extra) }
  }

  @inline(never)
  private mutating func grow(toFit needed: Int) {
    let next = max(capacity &* 2, needed)
    let replacement = UnsafeMutablePointer<UInt8>.allocate(capacity: next)
    replacement.initialize(from: base, count: count)
    base.deallocate()
    base = replacement
    capacity = next
  }

  // MARK: Appending

  @inline(__always)
  mutating func append(_ byte: UInt8) {
    reserve(1)
    base[count] = byte
    count &+= 1
  }

  /// A fixed fragment (`</`, `>`...): its bytes live in the binary, nothing is built.
  @inline(__always)
  mutating func append(_ fragment: StaticString) {
    append(fragment.utf8Start, count: fragment.utf8CodeUnitCount)
  }

  @inline(__always)
  mutating func append(_ bytes: UnsafePointer<UInt8>, count length: Int) {
    reserve(length)
    Self.copy(bytes, to: base + count, count: length)
    count &+= length
  }

  /// A copy of `length` bytes already written, starting at `offset` (a tag name for its closing tag).
  mutating func append(copyOf offset: Int, count length: Int) {
    reserve(length)
    Self.copy(base + offset, to: base + count, count: length)
    count &+= length
  }

  /// Names, values and fixed fragments are mostly a few bytes long, where a call to `memcpy` costs more than the copy:
  /// up to 16 bytes are moved as two overlapping words, longer runs go to `memcpy`. The source is read whole before the
  /// destination is written.
  @inline(__always)
  static func copy(_ source: UnsafePointer<UInt8>, to destination: UnsafeMutablePointer<UInt8>, count length: Int) {
    if length > 16 {
      destination.initialize(from: source, count: length)
      return
    }
    let from = UnsafeRawPointer(source)
    let to = UnsafeMutableRawPointer(destination)
    if length >= 8 {
      let head = from.loadUnaligned(as: UInt64.self)
      let tail = (from + (length &- 8)).loadUnaligned(as: UInt64.self)
      to.storeBytes(of: head, as: UInt64.self)
      (to + (length &- 8)).storeBytes(of: tail, as: UInt64.self)
    } else if length >= 4 {
      let head = from.loadUnaligned(as: UInt32.self)
      let tail = (from + (length &- 4)).loadUnaligned(as: UInt32.self)
      to.storeBytes(of: head, as: UInt32.self)
      (to + (length &- 4)).storeBytes(of: tail, as: UInt32.self)
    } else if length > 0 {
      let first = source[0], middle = source[length >> 1], last = source[length &- 1]
      destination[0] = first
      destination[length >> 1] = middle
      destination[length &- 1] = last
    }
  }

  /// The UTF-8 bytes of `string`, as they are.
  @inline(__always)
  mutating func append(utf8 string: String) {
    if string.utf8.withContiguousStorageIfAvailable({ (bytes: UnsafeBufferPointer<UInt8>) -> Void in
      if let start = bytes.baseAddress { append(start, count: bytes.count) }
    }) != nil { return }
    var owned = string
    owned.withUTF8 { bytes in
      if let start = bytes.baseAddress { append(start, count: bytes.count) }
    }
  }

  // MARK: Escaping

  // Text and attribute values keep the historical five-entity escaping (`& < > " '`); raw HTML stays an explicit
  // `_RenderNode` choice. The five characters sit between 0x22 and 0x3E, so one subtraction, one comparison and a bit
  // test sort every other byte (almost all of them) out. Runs without a special character are copied whole.
  // Bit n is set for the byte 0x22 + n: 0 is `"`, 4 is `&`, 5 is `'`, 26 is `<`, 28 is `>`.
  private static let specials: UInt32 = 0x1400_0031

  @inline(__always)
  mutating func appendEscaped(_ bytes: UnsafePointer<UInt8>, count length: Int) {
    var runStart = 0
    var index = 0
    while index < length {
      let offset = bytes[index] &- 0x22
      if offset < 29 && (Self.specials >> UInt32(offset)) & 1 != 0 {
        append(bytes + runStart, count: index &- runStart)
        switch bytes[index] {
        case 0x26: append("&amp;")
        case 0x3C: append("&lt;")
        case 0x3E: append("&gt;")
        case 0x22: append("&quot;")
        default: append("&#39;")
        }
        runStart = index &+ 1
      }
      index &+= 1
    }
    if runStart < length { append(bytes + runStart, count: length &- runStart) }
  }

  mutating func appendEscaped(_ string: String) {
    if string.utf8.withContiguousStorageIfAvailable({ (bytes: UnsafeBufferPointer<UInt8>) -> Void in
      if let start = bytes.baseAddress { appendEscaped(start, count: bytes.count) }
    }) != nil { return }
    var owned = string
    owned.withUTF8 { bytes in
      if let start = bytes.baseAddress { appendEscaped(start, count: bytes.count) }
    }
  }

  // MARK: Rewriting what was written

  mutating func truncate(to length: Int) { count = length }
}

extension String {
  /// `String(decoding: bytes, as: UTF8.self)`: the same string, ill-formed UTF-8 repaired with U+FFFD the same way.
  ///
  /// Not the generic `String(decoding:as:)`: with `UnsafeBufferPointer<UInt8>` it specializes a closure of the standard
  /// library's `_fromNonContiguousUnsafeBitcastUTF8Repairing<C>` in this module, and Embedded Swift serializes that
  /// specialization at a different place on some compiles, so this target's `.swiftmodule` changed without a source change
  /// and rebuilt everything that imports it (Documentation/Performance/BUILD_TIME.md, "The development loop").
  init(htmlUTF8 bytes: UnsafeBufferPointer<UInt8>) {
    self.init(unsafeUninitializedCapacity: bytes.count) { buffer in
      UnsafeMutableRawBufferPointer(buffer).copyMemory(from: UnsafeRawBufferPointer(bytes))
      return bytes.count
    }
  }
}
