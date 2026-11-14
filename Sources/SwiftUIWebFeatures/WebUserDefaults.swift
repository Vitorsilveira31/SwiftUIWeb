@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable
/// Foundation's `UserDefaults` for the browser (`UserDefaults` names it in the browser build; native
/// builds keep Foundation's). It is the app scope of `StorageRuntime`, which the
/// browser host keeps in `localStorage`; `@AppStorage` reads and writes through it, so a value set
/// here is the value an `@AppStorage` with the same key shows.
///
/// `localStorage` is readable by any script on the page and is not encrypted. Keep preferences
/// here, never secrets: secrets belong to `SwiftUIWebSecurity` (`SecItemAdd`), and sign-in sessions
/// to `HttpOnly` cookies the server sets.
///
/// Embedded Swift has no `Any`, so the typed accessors and setters replace `object(forKey:)` and
/// `register(defaults:)`.
public final class _WebUserDefaults: Sendable {
  public static let standard = _WebUserDefaults(prefix: "")

  private let prefix: String

  private init(prefix: String) { self.prefix = prefix }

  /// A named suite keeps its keys apart from the standard defaults. `nil` or an empty name is the
  /// standard suite.
  public convenience init?(suiteName: String?) {
    guard let suiteName, !suiteName.isEmpty else {
      self.init(prefix: "")
      return
    }
    self.init(prefix: "suite." + suiteName + ".")
  }

  func _storageKey(_ key: String) -> String { prefix + key }

  func _rawValue(forKey key: String) -> String? {
    StorageRuntime.read(_storageKey(key), scope: .app)
  }

  func _setRawValue(_ value: String, forKey key: String) {
    StorageRuntime.write(value, forKey: _storageKey(key), scope: .app)
  }

  public func string(forKey key: String) -> String? { _rawValue(forKey: key) }
  // Concrete conversions in the encoding `@AppStorage` uses: Embedded Swift cannot specialize the
  // generic storage codec's casts for every type.
  public func bool(forKey key: String) -> Bool {
    switch _rawValue(forKey: key)?.lowercased() {
    case "true", "1", "yes": return true
    default: return false
    }
  }
  public func integer(forKey key: String) -> Int { _rawValue(forKey: key).flatMap { Int($0) } ?? 0 }
  public func double(forKey key: String) -> Double { _rawValue(forKey: key).flatMap { Double($0) } ?? 0 }
  public func float(forKey key: String) -> Float { _rawValue(forKey: key).flatMap { Float($0) } ?? 0 }
  public func url(forKey key: String) -> URL? { _rawValue(forKey: key).flatMap { URL(string: $0) } }

  /// `object(forKey:) as? Bool` (and String, Int, Double): Embedded Swift has no `Any`, so the source lowering rewrites
  /// the cast into this typed read.
  public func _object<T: _DefaultsScalar>(forKey key: String, as type: T.Type) -> T? {
    _rawValue(forKey: key).flatMap { T._fromStoredString($0) }
  }

  /// Setting `nil` removes the key, as Foundation does.
  public func set(_ value: String?, forKey key: String) {
    guard let value else { removeObject(forKey: key); return }
    _setRawValue(value, forKey: key)
  }
  public func set(_ value: Bool, forKey key: String) { _setRawValue(value ? "true" : "false", forKey: key) }
  public func set(_ value: Int, forKey key: String) { _setRawValue(String(value), forKey: key) }
  public func set(_ value: Double, forKey key: String) { _setRawValue(String(value), forKey: key) }
  public func set(_ value: Float, forKey key: String) { _setRawValue(String(value), forKey: key) }
  public func set(_ value: [String], forKey key: String) { _setRawValue(_encodeStringArray(value), forKey: key) }
  public func set(_ value: URL?, forKey key: String) {
    guard let value else { removeObject(forKey: key); return }
    _setRawValue(value.absoluteString, forKey: key)
  }

  public func removeObject(forKey key: String) {
    _ = try? StorageRuntime.transaction([.remove(key: _storageKey(key))], scope: .app)
  }

  /// Asks the host to write pending values now. The browser host writes on its own schedule, so
  /// this is never required for correctness.
  @discardableResult
  public func synchronize() -> Bool {
    StorageRuntime.flush()
    return true
  }
}

public protocol _DefaultsScalar { static func _fromStoredString(_ raw: String) -> Self? }
extension Bool: _DefaultsScalar {
  public static func _fromStoredString(_ raw: String) -> Bool? {
    switch raw.lowercased() { case "true", "1", "yes": return true; case "false", "0", "no": return false; default: return nil }
  }
}
extension String: _DefaultsScalar { public static func _fromStoredString(_ raw: String) -> String? { raw } }
extension Array: _DefaultsScalar where Element == String {
  public static func _fromStoredString(_ raw: String) -> [String]? {
    if raw.hasPrefix(_framedArrayMarker) { return _decodeFramedStringArray(raw) }
    // The legacy form (before framing): elements joined with U+001F, which an element may itself contain.
    return raw.isEmpty ? [] : raw.split(separator: "\u{1F}", omittingEmptySubsequences: false).map { String($0) }
  }
}

/// Marks the framed form of a string array. A legacy value starts with the first element, which holds this marker only
/// when an application stored a string that starts with it.
private let _framedArrayMarker = "\u{1E}"

/// Each element is written as its UTF-8 byte count, the marker character, then its bytes, so an element that contains
/// U+001F or any other character reads back as it was written.
private func _encodeStringArray(_ value: [String]) -> String {
  var output = _framedArrayMarker
  for element in value {
    output += String(element.utf8.count) + _framedArrayMarker + element
  }
  return output
}

private func _decodeFramedStringArray(_ raw: String) -> [String]? {
  let bytes = Array(raw.utf8)
  let marker: UInt8 = 0x1E
  var index = 1
  var result: [String] = []
  while index < bytes.count {
    var length = 0
    var digits = 0
    while index < bytes.count, bytes[index] != marker {
      let byte = bytes[index]
      guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
      // Bounded by the bytes there are, before the next digit could overflow a 32-bit Int.
      let (scaled, overflowed) = length.multipliedReportingOverflow(by: 10)
      let (next, carried) = scaled.addingReportingOverflow(Int(byte - UInt8(ascii: "0")))
      guard !overflowed, !carried, next <= bytes.count else { return nil }
      length = next
      digits += 1
      index += 1
    }
    // The length is followed by the marker; an element of zero bytes needs no content.
    guard digits > 0, index < bytes.count, bytes[index] == marker else { return nil }
    index += 1
    guard length <= bytes.count - index else { return nil }
    result.append(String(decoding: bytes[index..<(index + length)], as: UTF8.self))
    index += length
  }
  return result
}
extension Int: _DefaultsScalar { public static func _fromStoredString(_ raw: String) -> Int? { Int(raw) } }
extension Double: _DefaultsScalar { public static func _fromStoredString(_ raw: String) -> Double? { Double(raw) } }

public typealias UserDefaults = _WebUserDefaults
