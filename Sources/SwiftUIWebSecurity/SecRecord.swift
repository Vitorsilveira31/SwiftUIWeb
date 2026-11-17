/// One keychain item: its stored attributes and its secret bytes. The whole record, attributes
/// included, is what the browser host encrypts, so not even a service or account name is readable
/// in IndexedDB.
struct _SecRecord: Sendable, Equatable {
  var id: String
  var attributes: [String: SecValue]
  var value: [UInt8]

  /// Two items with the same class, service, account and server are the same item.
  /// The most bytes the browser's secure store keeps for one item (Tools/BrowserIO/browser-io.mjs refuses more).
  static let byteLimit = 1_048_576

  var identity: [SecValue?] {
    [attributes[kSecClass], attributes[kSecAttrService], attributes[kSecAttrAccount], attributes[kSecAttrServer]]
  }

  /// Every item attribute the query names must be equal; result and limit keys are not attributes.
  func matches(_ query: [String: SecValue]) -> Bool {
    for (key, expected) in query where !_secQueryControls.contains(key) && key != kSecValueData {
      guard let stored = attributes[key], _secSameValue(stored, expected) else { return false }
    }
    return true
  }

  func dictionary(includingData: Bool) -> [String: SecValue] {
    var result = attributes
    if includingData { result[kSecValueData] = .data(value) }
    return result
  }

  // MARK: Encoding (version 1): u32 version, u32 count, then per attribute a key, a tag and its
  // payload, then the value bytes. Little-endian, lengths before bytes.

  func encoded() -> [UInt8] {
    var out: [UInt8] = []
    Self.u32(1, &out)
    Self.u32(UInt32(attributes.count), &out)
    for key in attributes.keys.sorted() {
      Self.bytes(Array(key.utf8), &out)
      switch attributes[key] ?? .bool(false) {
      case .string(let text): out.append(0); Self.bytes(Array(text.utf8), &out)
      case .data(let data): out.append(1); Self.bytes(data, &out)
      case .bool(let flag): out.append(2); out.append(flag ? 1 : 0)
      case .int(let number): out.append(3); Self.u64(UInt64(bitPattern: Int64(number)), &out)
      }
    }
    Self.bytes(value, &out)
    return out
  }

  static func decode(id: String, from bytes: [UInt8]) -> _SecRecord? {
    var reader = _SecRecordReader(bytes: bytes)
    guard reader.u32() == 1, let count = reader.u32(), count <= 64 else { return nil }
    var attributes: [String: SecValue] = .init()
    for _ in 0..<count {
      guard let key = reader.text(), let tag = reader.byte() else { return nil }
      switch tag {
      case 0: guard let text = reader.text() else { return nil }; attributes[key] = .string(text)
      case 1: guard let data = reader.data() else { return nil }; attributes[key] = .data(data)
      case 2: guard let flag = reader.byte() else { return nil }; attributes[key] = .bool(flag != 0)
      // Int is 32 bits in the browser build: a stored integer it cannot hold makes the record unreadable, not a trap.
      case 3: guard let raw = reader.u64(), let number = Int(exactly: Int64(bitPattern: raw)) else { return nil }; attributes[key] = .int(number)
      default: return nil
      }
    }
    guard let value = reader.data(), reader.isAtEnd else { return nil }
    return _SecRecord(id: id, attributes: attributes, value: value)
  }

  private static func u32(_ value: UInt32, _ out: inout [UInt8]) {
    for shift in stride(from: 0, to: 32, by: 8) { out.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
  }
  private static func u64(_ value: UInt64, _ out: inout [UInt8]) {
    u32(UInt32(truncatingIfNeeded: value), &out); u32(UInt32(truncatingIfNeeded: value >> 32), &out)
  }
  private static func bytes(_ value: [UInt8], _ out: inout [UInt8]) { u32(UInt32(value.count), &out); out.append(contentsOf: value) }
}

private struct _SecRecordReader {
  let bytes: [UInt8]
  var offset = 0
  var isAtEnd: Bool { offset == bytes.count }

  mutating func byte() -> UInt8? {
    guard offset < bytes.count else { return nil }
    defer { offset += 1 }
    return bytes[offset]
  }
  mutating func u32() -> UInt32? {
    guard bytes.count - offset >= 4 else { return nil }
    var value: UInt32 = 0
    for index in 0..<4 { value |= UInt32(bytes[offset + index]) << UInt32(index * 8) }
    offset += 4
    return value
  }
  mutating func u64() -> UInt64? {
    guard let low = u32(), let high = u32() else { return nil }
    return UInt64(low) | UInt64(high) << 32
  }
  mutating func data() -> [UInt8]? {
    // Compared before converting: a count past 2^31 would trap Int(_:) where Int is 32 bits.
    guard let raw = u32(), UInt64(raw) <= UInt64(bytes.count - offset) else { return nil }
    let count = Int(raw)
    defer { offset += count }
    return Array(bytes[offset ..< offset + count])
  }
  mutating func text() -> String? { data().map { String(decoding: $0, as: UTF8.self) } }
}

/// Query matching as Security.framework compares a CFBoolean and a CFNumber: `0` and `false`, `1` and `true` are equal.
func _secSameValue(_ stored: SecValue, _ expected: SecValue) -> Bool {
  if stored == expected { return true }
  switch (stored, expected) {
  case (.bool(let flag), .int(let number)), (.int(let number), .bool(let flag)): return number == (flag ? 1 : 0)
  default: return false
  }
}
