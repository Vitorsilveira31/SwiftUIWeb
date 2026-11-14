// A WASM-memory byte buffer the browser host writes into (or reads from)
// directly, instead of crossing the Swift/JS boundary once per byte.
//
// Ownership: Swift allocates and frees the storage; the host only borrows the
// pointer returned by an export, writes or reads `count` bytes right away, and
// must re-read `memory.buffer` after every call because growth may move it.
// The pointer is valid until the next call that reserves or resets this buffer.
// The type has no wasm-only code, so the native test suite exercises it too.
struct _EmbeddedByteBuffer {
  /// Hard cap (matches the host's 64 MiB HTML limit); larger requests fail.
  static let limit = 64 * 1024 * 1024

  private(set) var pointer: UnsafeMutablePointer<UInt8>?
  private(set) var capacity = 0
  private(set) var count = 0
  /// Bytes the host may have written since the last wipe: the length of the
  /// latest reservation. Only this prefix can hold text worth erasing.
  private var dirty = 0

  /// Capacity above which a buffer that grew for one large value (a paste, a
  /// drop payload) is released at the next wipe instead of staying that large.
  static let retainedCapacity = 64 * 1024

  /// Ensures room for `length` bytes with amortized doubling and returns the
  /// storage, or `nil` when the request exceeds the limit.
  mutating func reserve(_ length: Int) -> UnsafeMutablePointer<UInt8>? {
    guard length >= 0, length <= Self.limit else { return nil }
    if length > capacity || pointer == nil {
      let target = min(Self.limit, max(length, max(256, capacity * 2)))
      let next = UnsafeMutablePointer<UInt8>.allocate(capacity: target)
      // Contents are re-written by the host or by `store`; the old bytes may
      // be sensitive, so wipe them before releasing.
      zero()
      pointer?.deallocate()
      pointer = next
      capacity = target
    } else {
      zero()
    }
    count = 0
    dirty = length
    return pointer
  }

  /// Copies `bytes` in, replacing the contents. Returns false when the value is above the limit: the buffer then holds
  /// no value, and the caller sees the failure instead of an empty value.
  @discardableResult
  mutating func store(_ bytes: [UInt8]) -> Bool {
    guard let target = reserve(bytes.count) else { return false }
    bytes.withUnsafeBufferPointer { source in
      if let base = source.baseAddress { target.update(from: base, count: source.count) }
    }
    count = bytes.count
    dirty = max(dirty, bytes.count)
    return true
  }

  /// Records how many bytes of the reserved storage the host filled.
  mutating func commit(_ length: Int) { count = max(0, min(length, capacity)) }

  /// Zeroes the bytes that were written (secure-field text must not linger in
  /// memory) and gives back storage that grew far past what typing needs. The
  /// cost is proportional to the value, not to the capacity.
  mutating func wipe() {
    zero()
    if capacity > Self.retainedCapacity { release() }
  }

  /// Zeroes the written prefix and forgets the contents; keeps the storage.
  private mutating func zero() {
    if let pointer, capacity > 0 { pointer.update(repeating: 0, count: min(max(dirty, count), capacity)) }
    count = 0
    dirty = 0
  }

  mutating func release() {
    if let pointer, capacity > 0 { pointer.update(repeating: 0, count: min(max(dirty, count), capacity)) }
    pointer?.deallocate()
    pointer = nil
    capacity = 0
    count = 0
    dirty = 0
  }

  var address: UInt32 {
    guard let pointer else { return 0 }
    return UInt32(truncatingIfNeeded: UInt(bitPattern: pointer))
  }
}
