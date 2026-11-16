// Foundation's `JSONSerialization` for browser and Embedded builds. Parsing and printing use the JSON codec that
// backs the runtime's Codable-style coding (`_EmbeddedJSONCodec`), so both paths accept the same text.
// Results are Foundation-shaped Swift values: a JSON object is `[String: Any]`, an array is `[Any]`, a string is
// `String`, `true`/`false` are `Bool`, JSON null is `NSNull`. An integral number that fits `Int` is an `Int`, every
// other number a `Double`; `as? Double` on an integral value therefore fails here, while Foundation's `NSNumber`
// casts to both.
@_spi(Renderer) import SwiftUIWebTransferable

/// Foundation's JSON reader and writer. Apple declares this as an `open class` with class methods only.
open class JSONSerialization: NSObject {
  public struct ReadingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// Foundation returns mutable containers; Swift containers are values, so this option has no effect.
    public static let mutableContainers = ReadingOptions(rawValue: 1 << 0)
    /// Foundation returns mutable strings; Swift strings are values, so this option has no effect.
    public static let mutableLeaves = ReadingOptions(rawValue: 1 << 1)
    /// Accepts a top-level value that is neither an array nor an object.
    public static let fragmentsAllowed = ReadingOptions(rawValue: 1 << 2)
    public static let allowFragments = ReadingOptions(rawValue: 1 << 2)
    /// JSON5 input is not accepted by the runtime's codec, so this option has no effect.
    public static let json5Allowed = ReadingOptions(rawValue: 1 << 3)
    /// Parses a document whose top level is a dictionary without the braces; not supported, so this option has no effect.
    public static let topLevelDictionaryAssumed = ReadingOptions(rawValue: 1 << 4)
  }

  public struct WritingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// Two-space indentation with Foundation's `"key" : value` spacing.
    public static let prettyPrinted = WritingOptions(rawValue: 1 << 0)
    /// Object keys are always written in sorted order, so this option is implied.
    public static let sortedKeys = WritingOptions(rawValue: 1 << 1)
    /// Accepts a top-level value that is neither an array nor an object.
    public static let fragmentsAllowed = WritingOptions(rawValue: 1 << 2)
    /// Forward slashes are never escaped, so this option is implied.
    public static let withoutEscapingSlashes = WritingOptions(rawValue: 1 << 3)
  }

  /// Parses UTF-8 JSON text into Foundation-shaped values.
  public class func jsonObject(with data: Data, options opt: JSONSerialization.ReadingOptions = []) throws -> Any {
    let value = try _EmbeddedJSONCodec._parse(data)
    if !opt.contains(.fragmentsAllowed) {
      switch value {
      case .array, .object: break
      default: throw _JSONSerializationError.topLevelNotContainer
      }
    }
    return _foundationObject(value)
  }

  /// Writes an array or dictionary of JSON-compatible values as UTF-8 JSON text.
  public class func data(withJSONObject value: Any, options opt: JSONSerialization.WritingOptions = []) throws -> Data {
    guard let tree = _embeddedValue(value) else { throw _JSONSerializationError.invalidObject }
    if !opt.contains(.fragmentsAllowed) {
      switch tree {
      case .array, .object: break
      default: throw _JSONSerializationError.topLevelNotContainer
      }
    }
    if opt.contains(.prettyPrinted) {
      var text = ""
      _appendPretty(tree, depth: 0, to: &text)
      return Data(Array(text.utf8))
    }
    return try _EmbeddedJSONCodec._encode(tree)
  }

  /// Reads an open stream to its end and parses the text like `jsonObject(with:options:)`.
  ///
  /// Foundation raises an exception for a stream that is not open; here that is a precondition failure. A stream that
  /// failed reports its own error, and one with nothing left fails with the end-of-input parse error.
  public class func jsonObject(with stream: InputStream, options opt: JSONSerialization.ReadingOptions = []) throws -> Any {
    precondition(stream.streamStatus != .notOpen && stream.streamStatus != .closed, "stream is not open for reading")
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = chunk.withUnsafeMutableBufferPointer { stream.read($0.baseAddress!, maxLength: $0.count) }
      if count < 0 {
        if let error = stream.streamError { throw error }
        break
      }
      if count == 0 { break }
      bytes.append(contentsOf: chunk[0..<count])
    }
    return try jsonObject(with: Data(bytes), options: opt)
  }

  /// Serializes `obj` into an open output stream and returns the number of bytes written, or 0 for a value that is not
  /// valid JSON and -1 when the stream fails; `error` receives the reason. Foundation raises an exception for an
  /// invalid value or a stream that is not open; here the first reports through `error` (as `data(withJSONObject:)`
  /// throws instead of raising) and the second is a precondition failure.
  public class func writeJSONObject(_ obj: Any, to stream: OutputStream, options opt: JSONSerialization.WritingOptions = [], error reason: NSErrorPointer) -> Int {
    precondition(stream.streamStatus != .notOpen && stream.streamStatus != .closed, "stream is not open for writing")
    let data: Data
    do {
      data = try self.data(withJSONObject: obj, options: opt)
    } catch {
      // 3852 is NSPropertyListWriteInvalidError, the code Foundation uses for a value it cannot write.
      reason?.pointee = NSError(domain: NSCocoaErrorDomain, code: 3852, userInfo: ["NSDebugDescription": "Invalid object in JSON write"])
      return 0
    }
    // Foundation hands the stream one token at a time, so a full buffer stream keeps the tokens that fit.
    var total = 0
    for token in _jsonTokens(Array(data)) {
      var offset = 0
      while offset < token.count {
        let written = token.withUnsafeBufferPointer { stream.write($0.baseAddress! + offset, maxLength: token.count - offset) }
        if written <= 0 {
          let cause = stream.streamError as? NSError
          reason?.pointee = NSError(domain: NSCocoaErrorDomain, code: 512, userInfo: cause.map { ["NSUnderlyingError": $0] } ?? .init())
          return -1
        }
        offset += written
      }
      total += token.count
    }
    return total
  }

  /// Splits serialized JSON into the pieces Foundation writes: each structural character, each string, each run of
  /// whitespace and each other scalar run.
  private static func _jsonTokens(_ bytes: [UInt8]) -> [[UInt8]] {
    var tokens: [[UInt8]] = []
    var index = 0
    while index < bytes.count {
      let start = index
      let byte = bytes[index]
      index += 1
      switch byte {
      case UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: ","), UInt8(ascii: ":"):
        break
      case UInt8(ascii: "\""):
        while index < bytes.count {
          let next = bytes[index]
          index += 1
          if next == UInt8(ascii: "\\") { index += 1 } else if next == UInt8(ascii: "\"") { break }
        }
        index = min(index, bytes.count)
      case UInt8(ascii: " "), UInt8(ascii: "\n"):
        while index < bytes.count, bytes[index] == UInt8(ascii: " ") || bytes[index] == UInt8(ascii: "\n") { index += 1 }
      default:
        while index < bytes.count, !_isJSONDelimiter(bytes[index]) { index += 1 }
      }
      tokens.append(Array(bytes[start..<index]))
    }
    return tokens
  }

  private static func _isJSONDelimiter(_ byte: UInt8) -> Bool {
    switch byte {
    case UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: ","), UInt8(ascii: ":"),
      UInt8(ascii: "\""), UInt8(ascii: " "), UInt8(ascii: "\n"):
      return true
    default:
      return false
    }
  }

  /// Whether `obj` is an array or dictionary whose contents `data(withJSONObject:options:)` accepts.
  public class func isValidJSONObject(_ obj: Any) -> Bool {
    switch _embeddedValue(obj) {
    case .array?, .object?: return true
    default: return false
    }
  }

  private static func _foundationObject(_ value: _EmbeddedJSONValue) -> Any {
    switch value {
    case .null: return NSNull()
    case .bool(let flag): return flag
    case .number(let number):
      // A whole number the platform's Int holds is an Int, as Foundation's NSNumber answers `as? Int`; past 2^31 in the
      // browser build, where Int is 32 bits, it stays a Double instead of trapping.
      if number.rounded(.towardZero) == number, number >= -9_007_199_254_740_992, number <= 9_007_199_254_740_992,
        let whole = Int(exactly: number) {
        return whole
      }
      return number
    case .string(let text): return text
    case .array(let items):
      var result: [Any] = []
      result.reserveCapacity(items.count)
      for item in items { result.append(_foundationObject(item)) }
      return result
    case .object(let fields):
      var result: [String: Any] = .init()
      for (key, field) in fields { result[key] = _foundationObject(field) }
      return result
    }
  }

  /// The JSON tree for a Foundation-shaped value, or `nil` when it is not JSON-compatible (a non-finite number,
  /// an unknown type, or a container with an incompatible element).
  private static func _embeddedValue(_ value: Any) -> _EmbeddedJSONValue? {
    if value is NSNull { return .null }
    #if !hasFeature(Embedded)
    // `["b": nil] as [String: Any?]` widens to `[String: Any]` holding an empty Optional: Foundation writes null.
    // A present Optional unwraps through the casts below.
    if let optional = value as? any _JSONOptionalValue, optional._isNone { return .null }
    #endif
    if let text = value as? String { return .string(text) }
    if let flag = value as? Bool { return .bool(flag) }
    if let number = _number(value) { return number.isFinite ? .number(number) : nil }
    if let items = _array(value) {
      var tree: [_EmbeddedJSONValue] = []
      tree.reserveCapacity(items.count)
      for item in items {
        guard let element = _embeddedValue(item) else { return nil }
        tree.append(element)
      }
      return .array(tree)
    }
    if let fields = _dictionary(value) {
      var tree: [String: _EmbeddedJSONValue] = .init()
      for (key, field) in fields {
        guard let element = _embeddedValue(field) else { return nil }
        tree[key] = element
      }
      return .object(tree)
    }
    return nil
  }

  // Embedded Swift casts `Any` only to the exact type stored in it, so `["a": 1]` (a `[String: Int]`) is not a
  // `[String: Any]`. These ladders try the container types application code writes, widen the match to `Any` once,
  // and let `_embeddedValue` walk the result. Optional elements become JSON null.
  private static func _array(_ value: Any) -> [Any]? {
    if let items = value as? [Any] { return items }
    if let result = _widenedArray(value, String.self) { return result }
    if let result = _widenedArray(value, Int.self) { return result }
    if let result = _widenedArray(value, Int64.self) { return result }
    if let result = _widenedArray(value, Double.self) { return result }
    if let result = _widenedArray(value, Float.self) { return result }
    if let result = _widenedArray(value, Bool.self) { return result }
    if let result = _widenedArray(value, [String: Any].self) { return result }
    if let result = _widenedArray(value, [String: String].self) { return result }
    if let result = _widenedArray(value, [String: Int].self) { return result }
    if let result = _widenedArray(value, [Any].self) { return result }
    if let result = _widenedArray(value, [Int].self) { return result }
    if let result = _widenedArray(value, [String].self) { return result }
    if let result = _widenedArray(value, [Double].self) { return result }
    if let result = _widenedOptionalArray(value, Any.self) { return result }
    if let result = _widenedOptionalArray(value, String.self) { return result }
    if let result = _widenedOptionalArray(value, Int.self) { return result }
    if let result = _widenedOptionalArray(value, Double.self) { return result }
    if let result = _widenedOptionalArray(value, Bool.self) { return result }
    return nil
  }

  private static func _dictionary(_ value: Any) -> [String: Any]? {
    if let fields = value as? [String: Any] { return fields }
    if let result = _widenedDictionary(value, String.self) { return result }
    if let result = _widenedDictionary(value, Int.self) { return result }
    if let result = _widenedDictionary(value, Int64.self) { return result }
    if let result = _widenedDictionary(value, Double.self) { return result }
    if let result = _widenedDictionary(value, Float.self) { return result }
    if let result = _widenedDictionary(value, Bool.self) { return result }
    if let result = _widenedDictionary(value, NSNull.self) { return result }
    if let result = _widenedDictionary(value, [Any].self) { return result }
    if let result = _widenedDictionary(value, [String: Any].self) { return result }
    if let result = _widenedDictionary(value, [String].self) { return result }
    if let result = _widenedDictionary(value, [Int].self) { return result }
    if let result = _widenedDictionary(value, [String: String].self) { return result }
    if let result = _widenedDictionary(value, [String: Int].self) { return result }
    if let result = _widenedDictionary(value, [String: Double].self) { return result }
    if let result = _widenedDictionary(value, [String: Bool].self) { return result }
    if let result = _widenedOptionalDictionary(value, Any.self) { return result }
    if let result = _widenedOptionalDictionary(value, String.self) { return result }
    if let result = _widenedOptionalDictionary(value, Int.self) { return result }
    if let result = _widenedOptionalDictionary(value, Double.self) { return result }
    if let result = _widenedOptionalDictionary(value, Bool.self) { return result }
    return nil
  }

  private static func _widenedArray<T>(_ value: Any, _ type: T.Type) -> [Any]? {
    guard let items = value as? [T] else { return nil }
    var result: [Any] = []
    for item in items { result.append(item) }
    return result
  }

  private static func _widenedOptionalArray<T>(_ value: Any, _ type: T.Type) -> [Any]? {
    guard let items = value as? [T?] else { return nil }
    var result: [Any] = []
    for item in items {
      if let present = item { result.append(present) } else { result.append(NSNull()) }
    }
    return result
  }

  private static func _widenedDictionary<T>(_ value: Any, _ type: T.Type) -> [String: Any]? {
    guard let fields = value as? [String: T] else { return nil }
    var result: [String: Any] = .init()
    for (key, field) in fields { result[key] = field }
    return result
  }

  private static func _widenedOptionalDictionary<T>(_ value: Any, _ type: T.Type) -> [String: Any]? {
    guard let fields = value as? [String: T?] else { return nil }
    var result: [String: Any] = .init()
    for (key, field) in fields {
      if let present = field { result[key] = present } else { result[key] = NSNull() }
    }
    return result
  }

  private static func _number(_ value: Any) -> Double? {
    if let number = value as? Double { return number }
    if let number = value as? Int { return Double(number) }
    if let number = value as? Float { return Double(number) }
    if let number = value as? Int64 { return Double(number) }
    if let number = value as? Int32 { return Double(number) }
    if let number = value as? Int16 { return Double(number) }
    if let number = value as? Int8 { return Double(number) }
    if let number = value as? UInt { return Double(number) }
    if let number = value as? UInt64 { return Double(number) }
    if let number = value as? UInt32 { return Double(number) }
    if let number = value as? UInt16 { return Double(number) }
    if let number = value as? UInt8 { return Double(number) }
    return nil
  }

  /// Foundation's pretty layout: each element on its own line, two spaces per level, `"key" : value`.
  private static func _appendPretty(_ value: _EmbeddedJSONValue, depth: Int, to text: inout String) {
    switch value {
    case .array(let items):
      if items.isEmpty { text += "[]"; return }
      text += "[\n"
      for (index, item) in items.enumerated() {
        text += String(repeating: " ", count: 2 * (depth + 1))
        _appendPretty(item, depth: depth + 1, to: &text)
        text += index + 1 < items.count ? ",\n" : "\n"
      }
      text += String(repeating: " ", count: 2 * depth) + "]"
    case .object(let fields):
      if fields.isEmpty { text += "{}"; return }
      text += "{\n"
      let keys = fields.keys.sorted()
      for (index, key) in keys.enumerated() {
        text += String(repeating: " ", count: 2 * (depth + 1))
        text += _leaf(.string(key)) + " : "
        _appendPretty(fields[key] ?? .null, depth: depth + 1, to: &text)
        text += index + 1 < keys.count ? ",\n" : "\n"
      }
      text += String(repeating: " ", count: 2 * depth) + "}"
    default:
      text += _leaf(value)
    }
  }

  /// A scalar's canonical JSON text, produced by the same codec as compact output.
  private static func _leaf(_ value: _EmbeddedJSONValue) -> String {
    let bytes = (try? _EmbeddedJSONCodec._encode(value)) ?? Data()
    return String(decoding: Array(bytes), as: UTF8.self)
  }
}

/// Why `JSONSerialization` refused a value. Foundation reports these as `NSError`s; the browser stand-in keeps the
/// text internal and throws it as a plain `Error`.
package enum _JSONSerializationError: Error, CustomStringConvertible {
  case topLevelNotContainer
  case invalidObject

  package var description: String {
    switch self {
    case .topLevelNotContainer: return "JSON text did not start with array or object and option to allow fragments not set."
    case .invalidObject: return "Invalid top-level type in JSON write."
    }
  }
}

#if !hasFeature(Embedded)
/// Lets `JSONSerialization` tell an empty Optional stored in an `Any` from a value.
private protocol _JSONOptionalValue { var _isNone: Bool { get } }
extension Optional: _JSONOptionalValue {
  fileprivate var _isNone: Bool { self == nil }
}
#endif
