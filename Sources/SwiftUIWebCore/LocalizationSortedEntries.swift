// Translations compiled into one constant string sorted by key, so a large
// catalog lives in the binary's data section. An array or dictionary literal of
// the same entries is built by code at launch (about 60 KB of it for the
// studio's catalog); a `StaticString` is just bytes. `Tools/compile-strings.mjs`
// writes the blob.

/// A sorted translation blob plus the byte offset of each record, built in one
/// pass at registration. Lookups binary-search the offsets and compare in place.
///
/// Format: records sorted by the UTF-8 bytes of the key, each `key`, `keyEnd`,
/// `value`, then `recordEnd` (the last record may omit it). A plural value
/// starts with `pluralMarker`, then `category`, `categoryEnd`, text pairs
/// separated by `pluralMarker`.
struct LocalizationSortedEntries: Sendable {
  static let keyEnd: UInt8 = 3
  static let recordEnd: UInt8 = 4
  static let pluralMarker: UInt8 = 1
  static let categoryEnd: UInt8 = 2

  private let blob: StaticString
  private let starts: [Int]

  init(_ blob: StaticString) {
    self.blob = blob
    var starts: [Int] = []
    let count = blob.utf8CodeUnitCount
    if count > 0 {
      let bytes = blob.utf8Start
      starts.append(0)
      for index in 0..<count where bytes[index] == Self.recordEnd && index + 1 < count { starts.append(index + 1) }
    }
    self.starts = starts
  }

  func value(for key: String) -> LocalizedValue? {
    guard blob.utf8CodeUnitCount > 0 else { return nil }
    var low = 0
    var high = starts.count
    while low < high {
      let middle = (low + high) / 2
      let order = compare(key, at: starts[middle])
      if order == 0 { return decodeValue(at: starts[middle]) }
      if order < 0 { high = middle } else { low = middle + 1 }
    }
    return nil
  }

  private func compare(_ key: String, at start: Int) -> Int {
    let bytes = blob.utf8Start
    let count = blob.utf8CodeUnitCount
    var index = start
    for byte in key.utf8 {
      guard index < count, bytes[index] != Self.keyEnd else { return 1 }
      let candidate = bytes[index]
      if byte != candidate { return byte < candidate ? -1 : 1 }
      index += 1
    }
    return index < count && bytes[index] != Self.keyEnd ? -1 : 0
  }

  private func decodeValue(at start: Int) -> LocalizedValue {
    let bytes = blob.utf8Start
    let count = blob.utf8CodeUnitCount
    var begin = start
    while begin < count, bytes[begin] != Self.keyEnd { begin += 1 }
    begin += 1
    var end = begin
    while end < count, bytes[end] != Self.recordEnd { end += 1 }
    guard end > begin, bytes[begin] == Self.pluralMarker else { return .text(text(bytes, begin, end)) }
    var forms: [String: String] = .init()
    var form = begin + 1
    while form <= end {
      var formEnd = form
      while formEnd < end, bytes[formEnd] != Self.pluralMarker { formEnd += 1 }
      var split = form
      while split < formEnd, bytes[split] != Self.categoryEnd { split += 1 }
      if split < formEnd { forms[text(bytes, form, split)] = text(bytes, split + 1, formEnd) }
      form = formEnd + 1
    }
    return .plural(forms)
  }

  private func text(_ bytes: UnsafePointer<UInt8>, _ start: Int, _ end: Int) -> String {
    String(decoding: UnsafeBufferPointer(start: bytes + start, count: end - start), as: UTF8.self)
  }
}
