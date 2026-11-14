// Foundation-shaped JSON coders for every host. Full Swift encodes through Codable; Embedded Swift, which cannot
// reference Codable, encodes through EmbeddedCodable. They live next to `Data`, `Date` and `URL` so
// CodableRepresentation and the strategies can name them.

#if !hasFeature(Embedded)

// MARK: - Value tree

/// A parsed or encoded JSON value. Numbers keep their text, so 64-bit integers survive a round trip exactly; objects
/// keep their members in order, which is the order an encoder wrote them.
private indirect enum _JSONValue {
  case null
  case bool(Bool)
  case number(String)
  case string(String)
  case array([_JSONValue])
  case object([(key: String, value: _JSONValue)])

  var kindDescription: String {
    switch self {
    case .null: return "null"
    case .bool: return "bool"
    case .number: return "number"
    case .string: return "string"
    case .array: return "array"
    case .object: return "dictionary"
    }
  }
}

private struct _JSONKey: CodingKey {
  let stringValue: String
  let intValue: Int?
  init(stringValue: String) { self.stringValue = stringValue; intValue = nil }
  init(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
  init(index: Int) { stringValue = "Index \(index)"; intValue = index }
  static let `super` = _JSONKey(stringValue: "super")
}

// MARK: - Parser

private struct _JSONParser {
  let bytes: [UInt8]
  var index = 0
  /// Foundation rejects input nested deeper than 512 arrays and objects.
  private static let maximumDepth = 512

  /// An array or object being filled: parsing keeps these in an explicit stack instead of recursing, so the depth of the
  /// input never decides how much of the thread's stack is used (a few kilobytes of `[[[[…` would overflow it, and tasks
  /// run on small stacks).
  private struct Frame {
    var isObject: Bool
    var values: [_JSONValue] = []
    var members: [(key: String, value: _JSONValue)] = []
    var key = ""
  }

  init(_ data: Data) { bytes = data.toArray() }

  mutating func parse() throws -> _JSONValue {
    skipWhitespace()
    let value = try parseValue()
    skipWhitespace()
    guard index == bytes.count else { throw corrupted("Unexpected character after the top-level value.") }
    return value
  }

  private func corrupted(_ message: String) -> DecodingError {
    DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "The given data was not valid JSON. \(message)"))
  }

  private mutating func parseScalar() throws -> _JSONValue {
    guard let byte = peek else { throw corrupted("Unexpected end of input.") }
    switch byte {
    case 0x6e: return try parseLiteral("null", value: .null)
    case 0x74: return try parseLiteral("true", value: .bool(true))
    case 0x66: return try parseLiteral("false", value: .bool(false))
    case 0x22: return .string(try parseString())
    case 0x2d, 0x30...0x39: return try parseNumber()
    default: throw corrupted("Unexpected character at offset \(index).")
    }
  }

  private mutating func parseLiteral(_ literal: StaticString, value: _JSONValue) throws -> _JSONValue {
    let count = literal.utf8CodeUnitCount
    guard index + count <= bytes.count else { throw corrupted("Invalid literal at offset \(index).") }
    let matches = literal.withUTF8Buffer { expected in bytes[index..<(index + count)].elementsEqual(expected) }
    guard matches else { throw corrupted("Invalid literal at offset \(index).") }
    index += count
    return value
  }

  private mutating func parseString() throws -> String {
    index += 1
    var output: [UInt8] = []
    while let byte = peek {
      index += 1
      switch byte {
      case 0x22:
        // `String(decoding:)` would repair an invalid sequence into U+FFFD, silently changing the data (and merging
        // distinct malformed keys); Foundation rejects it.
        guard let string = String(validating: output, as: UTF8.self) else { throw corrupted("Invalid UTF-8 in a string at offset \(index - 1).") }
        return string
      case 0x5c:
        guard let escaped = peek else { throw corrupted("Unterminated escape sequence.") }
        index += 1
        switch escaped {
        case 0x22, 0x5c, 0x2f: output.append(escaped)
        case 0x62: output.append(0x08)
        case 0x66: output.append(0x0c)
        case 0x6e: output.append(0x0a)
        case 0x72: output.append(0x0d)
        case 0x74: output.append(0x09)
        case 0x75: output.append(contentsOf: String(try parseEscapedScalar()).utf8)
        default: throw corrupted("Invalid escape sequence at offset \(index - 1).")
        }
      case 0..<0x20: throw corrupted("Unescaped control character at offset \(index - 1).")
      default: output.append(byte)
      }
    }
    throw corrupted("Unterminated string.")
  }

  /// `\uXXXX`, joining a UTF-16 surrogate pair (`😀`) into one scalar.
  private mutating func parseEscapedScalar() throws -> Unicode.Scalar {
    let high = try parseHexQuad()
    if (0xD800...0xDBFF).contains(high) {
      guard index + 1 < bytes.count, bytes[index] == 0x5c, bytes[index + 1] == 0x75 else {
        throw corrupted("Unpaired UTF-16 surrogate.")
      }
      index += 2
      let low = try parseHexQuad()
      guard (0xDC00...0xDFFF).contains(low) else { throw corrupted("Unpaired UTF-16 surrogate.") }
      let value = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
      guard let scalar = Unicode.Scalar(value) else { throw corrupted("Invalid Unicode scalar.") }
      return scalar
    }
    guard let scalar = Unicode.Scalar(high) else { throw corrupted("Invalid Unicode scalar.") }
    return scalar
  }

  private mutating func parseHexQuad() throws -> UInt32 {
    guard index + 4 <= bytes.count else { throw corrupted("Short Unicode escape.") }
    var value: UInt32 = 0
    for _ in 0..<4 {
      let byte = bytes[index]
      let digit: UInt32
      switch byte {
      case 0x30...0x39: digit = UInt32(byte - 0x30)
      case 0x41...0x46: digit = UInt32(byte - 0x41) + 10
      case 0x61...0x66: digit = UInt32(byte - 0x61) + 10
      default: throw corrupted("Invalid Unicode escape.")
      }
      value = value * 16 + digit
      index += 1
    }
    return value
  }

  private mutating func parseNumber() throws -> _JSONValue {
    let start = index
    _ = consume(0x2d)
    if !consume(0x30) {
      guard consumeDigits() else { throw corrupted("Invalid number at offset \(start).") }
    }
    if consume(0x2e) {
      guard consumeDigits() else { throw corrupted("Invalid number at offset \(start).") }
    }
    if consume(0x65) || consume(0x45) {
      _ = consume(0x2b) || consume(0x2d)
      guard consumeDigits() else { throw corrupted("Invalid number at offset \(start).") }
    }
    return .number(String(decoding: bytes[start..<index], as: UTF8.self))
  }

  /// One JSON value, with arrays and objects parsed iteratively. `stack` holds the containers still open.
  private mutating func parseValue() throws -> _JSONValue {
    var stack: [Frame] = []
    while true {
      var finished: _JSONValue
      switch peek {
      case 0x5b?, 0x7b?:
        let isObject = peek == 0x7b
        index += 1
        guard stack.count < Self.maximumDepth else { throw corrupted("Too many nested arrays or dictionaries.") }
        skipWhitespace()
        if consume(isObject ? 0x7d : 0x5d) {
          finished = isObject ? .object([]) : .array([])
        } else {
          var frame = Frame(isObject: isObject)
          if isObject { frame.key = try parseMemberName() }
          stack.append(frame)
          continue
        }
      default:
        finished = try parseScalar()
      }
      // A value is complete: add it to the open container, closing containers while their end follows.
      while true {
        guard !stack.isEmpty else { return finished }
        let last = stack.count - 1
        skipWhitespace()
        if stack[last].isObject {
          stack[last].members.append((stack[last].key, finished))
          if consume(0x7d) { finished = .object(stack[last].members); stack.removeLast(); continue }
          guard consume(0x2c) else { throw corrupted("Expected ',' or '}' at offset \(index).") }
          skipWhitespace()
          stack[last].key = try parseMemberName()
        } else {
          stack[last].values.append(finished)
          if consume(0x5d) { finished = .array(stack[last].values); stack.removeLast(); continue }
          guard consume(0x2c) else { throw corrupted("Expected ',' or ']' at offset \(index).") }
          skipWhitespace()
        }
        break
      }
    }
  }

  /// `"name" :`, leaving the parser at the member's value.
  private mutating func parseMemberName() throws -> String {
    guard peek == 0x22 else { throw corrupted("Expected a member name at offset \(index).") }
    let key = try parseString()
    skipWhitespace()
    guard consume(0x3a) else { throw corrupted("Expected ':' at offset \(index).") }
    skipWhitespace()
    return key
  }

  private mutating func consumeDigits() -> Bool {
    let start = index
    while let byte = peek, (0x30...0x39).contains(byte) { index += 1 }
    return index != start
  }

  private mutating func skipWhitespace() {
    while let byte = peek, byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d { index += 1 }
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard peek == byte else { return false }
    index += 1
    return true
  }

  private var peek: UInt8? { index < bytes.count ? bytes[index] : nil }
}

// MARK: - Writer

private struct _JSONWriter {
  let options: JSONEncoder.OutputFormatting
  var output: [UInt8] = []

  mutating func write(_ value: _JSONValue, depth: Int = 0) {
    switch value {
    case .null: append("null")
    case .bool(let flag): append(flag ? "true" : "false")
    case .number(let text): append(text)
    case .string(let text): writeString(text)
    case .array(let values):
      guard !values.isEmpty else { append("[]"); return }
      output.append(0x5b)
      for (offset, element) in values.enumerated() {
        if offset > 0 { output.append(0x2c) }
        newline(depth + 1)
        write(element, depth: depth + 1)
      }
      newline(depth)
      output.append(0x5d)
    case .object(let members):
      guard !members.isEmpty else { append("{}"); return }
      let ordered = options.contains(.sortedKeys) ? members.sorted { $0.key < $1.key } : members
      output.append(0x7b)
      for (offset, member) in ordered.enumerated() {
        if offset > 0 { output.append(0x2c) }
        newline(depth + 1)
        writeString(member.key)
        append(options.contains(.prettyPrinted) ? " : " : ":")
        write(member.value, depth: depth + 1)
      }
      newline(depth)
      output.append(0x7d)
    }
  }

  private mutating func newline(_ depth: Int) {
    guard options.contains(.prettyPrinted) else { return }
    output.append(0x0a)
    output.append(contentsOf: repeatElement(0x20, count: depth * 2))
  }

  private mutating func append(_ text: String) { output.append(contentsOf: text.utf8) }

  /// Foundation's escaping: quotes, backslashes and control characters, and `/` unless `.withoutEscapingSlashes`.
  private mutating func writeString(_ text: String) {
    output.append(0x22)
    for byte in text.utf8 {
      switch byte {
      case 0x22: append("\\\"")
      case 0x5c: append("\\\\")
      case 0x2f: if options.contains(.withoutEscapingSlashes) { output.append(byte) } else { append("\\/") }
      case 0x08: append("\\b")
      case 0x0c: append("\\f")
      case 0x0a: append("\\n")
      case 0x0d: append("\\r")
      case 0x09: append("\\t")
      case 0..<0x20:
        let hex: [UInt8] = Array("0123456789abcdef".utf8)
        output.append(contentsOf: Array("\\u00".utf8))
        output.append(hex[Int(byte >> 4)])
        output.append(hex[Int(byte & 0x0f)])
      default: output.append(byte)
      }
    }
    output.append(0x22)
  }
}

// MARK: - ISO 8601

/// `yyyy-MM-dd'T'HH:mm:ssZ` in UTC, ISO8601DateFormatter's default (internet date-time, whole seconds).
private func _iso8601String(_ date: Date) -> String {
  // Written within years 1...9999 (the nearest bound for a date beyond them); Int64 of a non-finite value traps.
  let interval = date.timeIntervalSince1970
  let bounded = interval.isFinite ? Swift.min(Swift.max(interval, -62_135_596_800), 253_402_300_799) : 0
  let seconds = Int64(bounded.rounded(.down))
  let days = seconds >= 0 ? seconds / 86_400 : (seconds - 86_399) / 86_400
  let secondOfDay = seconds - days * 86_400
  let (year, month, day) = _civilDate(fromDays: days)
  func pad(_ value: Int64, _ width: Int) -> String {
    let text = String(value)
    return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
  }
  return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(pad(secondOfDay / 3600, 2)):\(pad(secondOfDay / 60 % 60, 2)):\(pad(secondOfDay % 60, 2))Z"
}

/// Parses `yyyy-MM-ddTHH:mm:ss` followed by `Z` or `±HH:mm`, optionally with fractional seconds.
private func _iso8601Date(_ text: String) -> Date? {
  let chars = Array(text.utf8)
  func number(_ start: Int, _ count: Int) -> Int64? {
    guard start + count <= chars.count else { return nil }
    var value: Int64 = 0
    for byte in chars[start..<(start + count)] {
      guard (0x30...0x39).contains(byte) else { return nil }
      value = value * 10 + Int64(byte - 0x30)
    }
    return value
  }
  guard chars.count >= 20, chars[4] == 0x2d, chars[7] == 0x2d, chars[10] == 0x54 || chars[10] == 0x74,
        chars[13] == 0x3a, chars[16] == 0x3a,
        let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
        let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
        (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61 else { return nil }
  var index = 19
  var fraction = 0.0
  if index < chars.count, chars[index] == 0x2e {
    index += 1
    var scale = 0.1
    let start = index
    while index < chars.count, (0x30...0x39).contains(chars[index]) {
      fraction += Double(chars[index] - 0x30) * scale
      scale /= 10
      index += 1
    }
    guard index > start else { return nil }
  }
  var offset: Int64 = 0
  guard index < chars.count else { return nil }
  switch chars[index] {
  case 0x5a, 0x7a: index += 1
  case 0x2b, 0x2d:
    let sign: Int64 = chars[index] == 0x2d ? -1 : 1
    guard let hours = number(index + 1, 2) else { return nil }
    var minutesStart = index + 3
    if minutesStart < chars.count, chars[minutesStart] == 0x3a { minutesStart += 1 }
    guard let minutes = number(minutesStart, 2) else { return nil }
    offset = sign * (hours * 3600 + minutes * 60)
    index = minutesStart + 2
  default: return nil
  }
  guard index == chars.count else { return nil }
  let days = _days(fromCivilYear: year, month: month, day: day)
  let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset
  return Date(timeIntervalSince1970: Double(seconds) + fraction)
}

/// Days since 1970-01-01 to a proleptic Gregorian date (Howard Hinnant's `civil_from_days`).
private func _civilDate(fromDays days: Int64) -> (Int64, Int64, Int64) {
  let z = days + 719_468
  let era = (z >= 0 ? z : z - 146_096) / 146_097
  let dayOfEra = z - era * 146_097
  let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
  let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
  let monthPrime = (5 * dayOfYear + 2) / 153
  let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
  let month = monthPrime < 10 ? monthPrime + 3 : monthPrime - 9
  return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
}

private func _days(fromCivilYear year: Int64, month: Int64, day: Int64) -> Int64 {
  let y = month <= 2 ? year - 1 : year
  let era = (y >= 0 ? y : y - 399) / 400
  let yearOfEra = y - era * 400
  let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
  let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
  return era * 146_097 + dayOfEra - 719_468
}

/// Foundation's text for a floating-point number: its shortest round-tripping form, without a trailing `.0`.
private func _jsonNumberText<F: BinaryFloatingPoint & LosslessStringConvertible>(_ value: F) -> String {
  var text = value.description
  if text.hasSuffix(".0") { text.removeLast(2) }
  return text
}

// MARK: - Encoder

/// Foundation's `JSONEncoder`: the same strategies and output formatting, writing UTF-8 JSON `Data`.
open class JSONEncoder: @unchecked Sendable {
  public struct OutputFormatting: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let prettyPrinted = OutputFormatting(rawValue: 1 << 0)
    public static let sortedKeys = OutputFormatting(rawValue: 1 << 1)
    public static let withoutEscapingSlashes = OutputFormatting(rawValue: 1 << 3)
  }

  public enum DateEncodingStrategy: Sendable {
    case deferredToDate
    case secondsSince1970
    case millisecondsSince1970
    case iso8601
    @preconcurrency case custom(@Sendable (_ date: Date, _ encoder: any Encoder) throws -> Void)
  }

  public enum DataEncodingStrategy: Sendable {
    case deferredToData
    case base64
    @preconcurrency case custom(@Sendable (_ data: Data, _ encoder: any Encoder) throws -> Void)
  }

  public enum NonConformingFloatEncodingStrategy: Sendable {
    case `throw`
    case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
  }

  public enum KeyEncodingStrategy: Sendable {
    case useDefaultKeys
    case convertToSnakeCase
    @preconcurrency case custom(@Sendable (_ codingPath: [any CodingKey]) -> any CodingKey)
  }

  open var outputFormatting: OutputFormatting = []
  open var dateEncodingStrategy: DateEncodingStrategy = .deferredToDate
  open var dataEncodingStrategy: DataEncodingStrategy = .base64
  open var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .throw
  open var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys
  @preconcurrency open var userInfo: [CodingUserInfoKey: any Sendable] = [:]

  public init() {}

  open func encode<T: Encodable>(_ value: T) throws -> Data {
    let options = _JSONEncodingOptions(self)
    let root = try _JSONEncoderImpl(options: options, codingPath: []).box(value, codingPath: [])
    var writer = _JSONWriter(options: outputFormatting)
    writer.write(root.resolved)
    return Data(writer.output)
  }
}

private struct _JSONEncodingOptions {
  let dateStrategy: JSONEncoder.DateEncodingStrategy
  let dataStrategy: JSONEncoder.DataEncodingStrategy
  let floatStrategy: JSONEncoder.NonConformingFloatEncodingStrategy
  let keyStrategy: JSONEncoder.KeyEncodingStrategy
  let userInfo: [CodingUserInfoKey: Any]

  init(_ encoder: JSONEncoder) {
    dateStrategy = encoder.dateEncodingStrategy
    dataStrategy = encoder.dataEncodingStrategy
    floatStrategy = encoder.nonConformingFloatEncodingStrategy
    keyStrategy = encoder.keyEncodingStrategy
    userInfo = encoder.userInfo.mapValues { $0 as Any }
  }
}

/// A value under construction. Containers hand out references so nested containers and super encoders can keep
/// writing after their parent has stored them.
private enum _JSONFuture {
  case value(_JSONValue)
  case array(_JSONArrayRef)
  case object(_JSONObjectRef)
  case encoder(_JSONEncoderImpl)

  var resolved: _JSONValue {
    switch self {
    case .value(let value): return value
    case .array(let array): return .array(array.items.map(\.resolved))
    case .object(let object): return .object(object.keys.map { (key: $0, value: object.values[$0]!.resolved) })
    case .encoder(let encoder): return encoder.storage?.resolved ?? .object([])
    }
  }
}

private final class _JSONArrayRef {
  var items: [_JSONFuture] = []
}

private final class _JSONObjectRef {
  var keys: [String] = []
  var values: [String: _JSONFuture] = [:]
  func set(_ key: String, _ value: _JSONFuture) {
    if values.updateValue(value, forKey: key) == nil { keys.append(key) }
  }
}

private final class _JSONEncoderImpl: Encoder {
  let options: _JSONEncodingOptions
  let codingPath: [any CodingKey]
  var storage: _JSONFuture?
  /// The encoder of a `[String: V]`: its keys are data, so the key strategy leaves them alone (Foundation's rule).
  let preservesKeys: Bool
  var userInfo: [CodingUserInfoKey: Any] { options.userInfo }

  init(options: _JSONEncodingOptions, codingPath: [any CodingKey], preservesKeys: Bool = false) {
    self.options = options
    self.codingPath = codingPath
    self.preservesKeys = preservesKeys
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    let object: _JSONObjectRef
    if case .object(let existing)? = storage {
      object = existing
    } else {
      object = _JSONObjectRef()
      storage = .object(object)
    }
    return KeyedEncodingContainer(_JSONKeyedEncodingContainer<Key>(impl: self, object: object, codingPath: codingPath))
  }

  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    let array: _JSONArrayRef
    if case .array(let existing)? = storage {
      array = existing
    } else {
      array = _JSONArrayRef()
      storage = .array(array)
    }
    return _JSONUnkeyedEncodingContainer(impl: self, array: array, codingPath: codingPath)
  }

  func singleValueContainer() -> any SingleValueEncodingContainer {
    _JSONSingleValueEncodingContainer(impl: self, codingPath: codingPath)
  }

  /// `value` as a JSON value: Foundation's special cases (dates, data, URLs, floats) first, then its own encoding.
  func box<T: Encodable>(_ value: T, codingPath: [any CodingKey]) throws -> _JSONFuture {
    switch value {
    case let string as String: return .value(.string(string))
    case let flag as Bool: return .value(.bool(flag))
    case let number as Int: return .value(.number(String(number)))
    case let number as Int8: return .value(.number(String(number)))
    case let number as Int16: return .value(.number(String(number)))
    case let number as Int32: return .value(.number(String(number)))
    case let number as Int64: return .value(.number(String(number)))
    case let number as UInt: return .value(.number(String(number)))
    case let number as UInt8: return .value(.number(String(number)))
    case let number as UInt16: return .value(.number(String(number)))
    case let number as UInt32: return .value(.number(String(number)))
    case let number as UInt64: return .value(.number(String(number)))
    case let number as Double: return try boxFloat(number, codingPath: codingPath)
    case let number as Float: return try boxFloat(number, codingPath: codingPath)
    case let url as URL: return .value(.string(url.absoluteString))
    case let date as Date: return try boxDate(date, codingPath: codingPath)
    case let data as Data: return try boxData(data, codingPath: codingPath)
    default:
      let nested = _JSONEncoderImpl(options: options, codingPath: codingPath, preservesKeys: value is any _JSONStringKeyedDictionary)
      try value.encode(to: nested)
      return .encoder(nested)
    }
  }

  private func boxFloat<F: BinaryFloatingPoint & LosslessStringConvertible>(_ value: F, codingPath: [any CodingKey]) throws -> _JSONFuture {
    guard value.isFinite else {
      guard case .convertToString(let positiveInfinity, let negativeInfinity, let nan) = options.floatStrategy else {
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Unable to encode \(F.self).\(value) directly in JSON. Use JSONEncoder.NonConformingFloatEncodingStrategy.convertToString to specify how the value should be encoded."))
      }
      return .value(.string(value.isNaN ? nan : (value > 0 ? positiveInfinity : negativeInfinity)))
    }
    return .value(.number(_jsonNumberText(value)))
  }

  private func boxDate(_ date: Date, codingPath: [any CodingKey]) throws -> _JSONFuture {
    switch options.dateStrategy {
    case .deferredToDate:
      let nested = _JSONEncoderImpl(options: options, codingPath: codingPath)
      try date.encode(to: nested)
      return .encoder(nested)
    case .secondsSince1970: return try boxFloat(date.timeIntervalSince1970, codingPath: codingPath)
    case .millisecondsSince1970: return try boxFloat(date.timeIntervalSince1970 * 1000, codingPath: codingPath)
    case .iso8601: return .value(.string(_iso8601String(date)))
    case .custom(let closure):
      let nested = _JSONEncoderImpl(options: options, codingPath: codingPath)
      try closure(date, nested)
      return .encoder(nested)
    }
  }

  private func boxData(_ data: Data, codingPath: [any CodingKey]) throws -> _JSONFuture {
    switch options.dataStrategy {
    case .deferredToData:
      let nested = _JSONEncoderImpl(options: options, codingPath: codingPath)
      try data.encode(to: nested)
      return .encoder(nested)
    case .base64: return .value(.string(data.base64EncodedString()))
    case .custom(let closure):
      let nested = _JSONEncoderImpl(options: options, codingPath: codingPath)
      try closure(data, nested)
      return .encoder(nested)
    }
  }

  func key(_ key: some CodingKey, codingPath: [any CodingKey]) -> String {
    if preservesKeys { return key.stringValue }
    switch options.keyStrategy {
    case .useDefaultKeys: return key.stringValue
    case .convertToSnakeCase: return _EmbeddedKeyCase.snakeFromCamel(key.stringValue)
    case .custom(let transform): return transform(codingPath + [key]).stringValue
    }
  }
}

private struct _JSONSingleValueEncodingContainer: SingleValueEncodingContainer {
  let impl: _JSONEncoderImpl
  let codingPath: [any CodingKey]
  mutating func encodeNil() throws { impl.storage = .value(.null) }
  mutating func encode<T: Encodable>(_ value: T) throws { impl.storage = try impl.box(value, codingPath: codingPath) }
}

private struct _JSONKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let impl: _JSONEncoderImpl
  let object: _JSONObjectRef
  let codingPath: [any CodingKey]

  mutating func encodeNil(forKey key: Key) throws { object.set(impl.key(key, codingPath: codingPath), .value(.null)) }
  mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
    object.set(impl.key(key, codingPath: codingPath), try impl.box(value, codingPath: codingPath + [key]))
  }
  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
    let nested = _JSONObjectRef()
    object.set(impl.key(key, codingPath: codingPath), .object(nested))
    return KeyedEncodingContainer(_JSONKeyedEncodingContainer<NestedKey>(impl: impl, object: nested, codingPath: codingPath + [key]))
  }
  mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
    let nested = _JSONArrayRef()
    object.set(impl.key(key, codingPath: codingPath), .array(nested))
    return _JSONUnkeyedEncodingContainer(impl: impl, array: nested, codingPath: codingPath + [key])
  }
  mutating func superEncoder() -> any Encoder { superEncoder(named: _JSONKey.super) }
  mutating func superEncoder(forKey key: Key) -> any Encoder { superEncoder(named: key) }
  private mutating func superEncoder(named key: some CodingKey) -> any Encoder {
    let nested = _JSONEncoderImpl(options: impl.options, codingPath: codingPath + [key])
    object.set(impl.key(key, codingPath: codingPath), .encoder(nested))
    return nested
  }
}

private struct _JSONUnkeyedEncodingContainer: UnkeyedEncodingContainer {
  let impl: _JSONEncoderImpl
  let array: _JSONArrayRef
  let codingPath: [any CodingKey]
  var count: Int { array.items.count }

  mutating func encodeNil() throws { array.items.append(.value(.null)) }
  mutating func encode<T: Encodable>(_ value: T) throws {
    array.items.append(try impl.box(value, codingPath: codingPath + [_JSONKey(index: count)]))
  }
  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
    let path = codingPath + [_JSONKey(index: count)]
    let nested = _JSONObjectRef()
    array.items.append(.object(nested))
    return KeyedEncodingContainer(_JSONKeyedEncodingContainer<NestedKey>(impl: impl, object: nested, codingPath: path))
  }
  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    let path = codingPath + [_JSONKey(index: count)]
    let nested = _JSONArrayRef()
    array.items.append(.array(nested))
    return _JSONUnkeyedEncodingContainer(impl: impl, array: nested, codingPath: path)
  }
  mutating func superEncoder() -> any Encoder {
    let nested = _JSONEncoderImpl(options: impl.options, codingPath: codingPath + [_JSONKey(index: count)])
    array.items.append(.encoder(nested))
    return nested
  }
}

// MARK: - Decoder

/// Foundation's `JSONDecoder`: the same strategies, reading UTF-8 JSON `Data` and throwing `DecodingError`.
open class JSONDecoder: @unchecked Sendable {
  public enum DateDecodingStrategy: Sendable {
    case deferredToDate
    case secondsSince1970
    case millisecondsSince1970
    case iso8601
    @preconcurrency case custom(@Sendable (_ decoder: any Decoder) throws -> Date)
  }

  public enum DataDecodingStrategy: Sendable {
    case deferredToData
    case base64
    @preconcurrency case custom(@Sendable (_ decoder: any Decoder) throws -> Data)
  }

  public enum NonConformingFloatDecodingStrategy: Sendable {
    case `throw`
    case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
  }

  public enum KeyDecodingStrategy: Sendable {
    case useDefaultKeys
    case convertFromSnakeCase
    @preconcurrency case custom(@Sendable (_ codingPath: [any CodingKey]) -> any CodingKey)
  }

  open var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
  open var dataDecodingStrategy: DataDecodingStrategy = .base64
  open var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .throw
  open var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
  @preconcurrency open var userInfo: [CodingUserInfoKey: any Sendable] = [:]

  public init() {}

  open func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    var parser = _JSONParser(data)
    let root = try parser.parse()
    return try _JSONDecoderImpl(value: root, options: _JSONDecodingOptions(self), codingPath: []).unbox(root, as: type, codingPath: [])
  }
}

private struct _JSONDecodingOptions {
  let dateStrategy: JSONDecoder.DateDecodingStrategy
  let dataStrategy: JSONDecoder.DataDecodingStrategy
  let floatStrategy: JSONDecoder.NonConformingFloatDecodingStrategy
  let keyStrategy: JSONDecoder.KeyDecodingStrategy
  let userInfo: [CodingUserInfoKey: Any]

  init(_ decoder: JSONDecoder) {
    dateStrategy = decoder.dateDecodingStrategy
    dataStrategy = decoder.dataDecodingStrategy
    floatStrategy = decoder.nonConformingFloatDecodingStrategy
    keyStrategy = decoder.keyDecodingStrategy
    userInfo = decoder.userInfo.mapValues { $0 as Any }
  }
}

private final class _JSONDecoderImpl: Decoder, SingleValueDecodingContainer {
  let value: _JSONValue
  let options: _JSONDecodingOptions
  let codingPath: [any CodingKey]
  /// The decoder of a `[String: V]`: its keys are data, so the key strategy leaves them alone (Foundation's rule).
  let preservesKeys: Bool
  var userInfo: [CodingUserInfoKey: Any] { options.userInfo }

  init(value: _JSONValue, options: _JSONDecodingOptions, codingPath: [any CodingKey], preservesKeys: Bool = false) {
    self.value = value
    self.options = options
    self.codingPath = codingPath
    self.preservesKeys = preservesKeys
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard case .object(let members) = value else {
      throw typeMismatch([String: Any].self, value, codingPath: codingPath)
    }
    var object: [String: _JSONValue] = [:]
    for member in members {
      let key: String
      switch preservesKeys ? .useDefaultKeys : options.keyStrategy {
      case .useDefaultKeys: key = member.key
      case .convertFromSnakeCase: key = _EmbeddedKeyCase.camelFromSnake(member.key)
      case .custom(let transform): key = transform(codingPath + [_JSONKey(stringValue: member.key)]).stringValue
      }
      object[key] = member.value
    }
    return KeyedDecodingContainer(_JSONKeyedDecodingContainer<Key>(impl: self, object: object, codingPath: codingPath))
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard case .array(let values) = value else { throw typeMismatch([Any].self, value, codingPath: codingPath) }
    return _JSONUnkeyedDecodingContainer(impl: self, values: values, codingPath: codingPath)
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer { self }

  // SingleValueDecodingContainer
  func decodeNil() -> Bool { if case .null = value { return true }; return false }
  func decode<T: Decodable>(_ type: T.Type) throws -> T { try unbox(value, as: type, codingPath: codingPath) }

  /// `value` as `T`: Foundation's special cases (numbers, dates, data, URLs) first, then `T`'s own decoding.
  /// Foundation's rule for `null`: the types it decodes itself (strings, numbers, booleans, URLs, dates and data)
  /// find their value missing; every other type gets the null through its own `init(from:)`.
  func unbox<T: Decodable>(_ value: _JSONValue, as type: T.Type, codingPath: [any CodingKey]) throws -> T {
    if case .null = value, T.self is any _JSONBuiltIn.Type {
      throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected \(T.self) value but found null instead."))
    }
    if T.self == String.self {
      guard case .string(let string) = value else { throw typeMismatch(T.self, value, codingPath: codingPath) }
      return string as! T
    }
    if T.self == Bool.self {
      guard case .bool(let flag) = value else { throw typeMismatch(T.self, value, codingPath: codingPath) }
      return flag as! T
    }
    if let integer = T.self as? any _JSONInteger.Type { return try unboxInteger(integer, value, codingPath: codingPath) as! T }
    if T.self == Double.self { return try unboxFloat(Double.self, value, codingPath: codingPath) as! T }
    if T.self == Float.self { return try unboxFloat(Float.self, value, codingPath: codingPath) as! T }
    if T.self == URL.self {
      guard case .string(let string) = value else { throw typeMismatch(T.self, value, codingPath: codingPath) }
      guard let url = URL(string: string) else {
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Invalid URL string."))
      }
      return url as! T
    }
    if T.self == Date.self { return try unboxDate(value, codingPath: codingPath) as! T }
    if T.self == Data.self { return try unboxData(value, codingPath: codingPath) as! T }
    return try T(from: _JSONDecoderImpl(value: value, options: options, codingPath: codingPath, preservesKeys: T.self is any _JSONStringKeyedDictionary.Type))
  }

  private func unboxInteger<I: _JSONInteger>(_ type: I.Type, _ value: _JSONValue, codingPath: [any CodingKey]) throws -> I {
    guard case .number(let text) = value else { throw typeMismatch(I.self, value, codingPath: codingPath) }
    if let exact = I(text) { return exact }
    // An integral number written with a fraction or an exponent (`2.0`, `5e3`): its exact digits, never a Double, which
    // would round anything above 2^53.
    if let digits = _jsonIntegralDigits(text), let exact = I(digits) { return exact }
    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(text)> does not fit in \(I.self)."))
  }

  private func unboxFloat<F: BinaryFloatingPoint & LosslessStringConvertible>(_ type: F.Type, _ value: _JSONValue, codingPath: [any CodingKey]) throws -> F {
    switch value {
    case .number(let text):
      guard let number = F(text) else { throw typeMismatch(F.self, value, codingPath: codingPath) }
      // A number beyond the type's range parses as infinity; only the string strategy may produce a non-finite value.
      guard number.isFinite else {
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(text)> does not fit in \(F.self)."))
      }
      return number
    case .string(let text):
      if case .convertFromString(let positiveInfinity, let negativeInfinity, let nan) = options.floatStrategy {
        if text == positiveInfinity { return .infinity }
        if text == negativeInfinity { return -.infinity }
        if text == nan { return .nan }
      }
      throw typeMismatch(F.self, value, codingPath: codingPath)
    default: throw typeMismatch(F.self, value, codingPath: codingPath)
    }
  }

  private func unboxDate(_ value: _JSONValue, codingPath: [any CodingKey]) throws -> Date {
    let nested = _JSONDecoderImpl(value: value, options: options, codingPath: codingPath)
    switch options.dateStrategy {
    case .deferredToDate: return try Date(from: nested)
    case .secondsSince1970: return Date(timeIntervalSince1970: try unboxFloat(Double.self, value, codingPath: codingPath))
    case .millisecondsSince1970: return Date(timeIntervalSince1970: try unboxFloat(Double.self, value, codingPath: codingPath) / 1000)
    case .iso8601:
      guard case .string(let text) = value else { throw typeMismatch(String.self, value, codingPath: codingPath) }
      guard let date = _iso8601Date(text) else {
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Expected date string to be ISO8601-formatted."))
      }
      return date
    case .custom(let closure): return try closure(nested)
    }
  }

  private func unboxData(_ value: _JSONValue, codingPath: [any CodingKey]) throws -> Data {
    let nested = _JSONDecoderImpl(value: value, options: options, codingPath: codingPath)
    switch options.dataStrategy {
    case .deferredToData: return try Data(from: nested)
    case .base64:
      guard case .string(let text) = value else { throw typeMismatch(String.self, value, codingPath: codingPath) }
      guard let data = Data(base64Encoded: text) else {
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Encountered Data is not valid Base64."))
      }
      return data
    case .custom(let closure): return try closure(nested)
    }
  }

  func typeMismatch(_ type: Any.Type, _ value: _JSONValue, codingPath: [any CodingKey]) -> DecodingError {
    DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode \(type) but found \(value.kindDescription) instead."))
  }
}

/// The types the decoder reads itself, which a JSON `null` cannot stand for.
/// The integer a JSON number with a fraction or an exponent stands for, as decimal digits (`"-12.50e1"` is `"-125"`),
/// or nil when it is not integral. Exact: no floating-point step. More than 40 digits is nil, since no integer type
/// holds it, which also keeps `1e100000` from building a long string.
private func _jsonIntegralDigits(_ text: String) -> String? {
  var utf8 = Substring(text).utf8[...]
  var negative = false
  if utf8.first == UInt8(ascii: "-") { negative = true; utf8 = utf8.dropFirst() }
  var mantissa: [UInt8] = []
  var point: Int?
  var exponent = 0
  var index = utf8.startIndex
  while index != utf8.endIndex {
    let byte = utf8[index]
    if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
      mantissa.append(byte)
    } else if byte == UInt8(ascii: "."), point == nil {
      point = mantissa.count
    } else if byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") {
      guard let parsed = Int(String(Substring(utf8[utf8.index(after: index)...]))) else { return nil }
      exponent = parsed
      break
    } else {
      return nil
    }
    index = utf8.index(after: index)
  }
  guard !mantissa.isEmpty else { return nil }
  // The decimal point after shifting by the exponent: digits before it are the integer, those after must be zeros.
  let (shifted, overflow) = (point ?? mantissa.count).addingReportingOverflow(exponent)
  let zero = UInt8(ascii: "0")
  guard !overflow else { return mantissa.allSatisfy { $0 == zero } ? "0" : nil }
  let split = max(0, min(shifted, mantissa.count))
  guard mantissa[split...].allSatisfy({ $0 == zero }) else { return nil }
  var digits = Array(mantissa[..<split].drop { $0 == zero })
  if digits.isEmpty { return "0" }
  let padding = shifted - mantissa.count
  if padding > 0 {
    guard digits.count + padding <= 40 else { return nil }
    digits.append(contentsOf: repeatElement(zero, count: padding))
  }
  guard digits.count <= 40 else { return nil }
  return (negative ? "-" : "") + String(decoding: digits, as: UTF8.self)
}

/// `[String: V]`, whose keys the key strategies must not convert.
private protocol _JSONStringKeyedDictionary {}
extension Dictionary: _JSONStringKeyedDictionary where Key == String {}

private protocol _JSONBuiltIn {}
extension String: _JSONBuiltIn {}
extension Bool: _JSONBuiltIn {}
extension Double: _JSONBuiltIn {}
extension Float: _JSONBuiltIn {}
extension URL: _JSONBuiltIn {}
extension Date: _JSONBuiltIn {}
extension Data: _JSONBuiltIn {}

private protocol _JSONInteger: FixedWidthInteger, _JSONBuiltIn {}
extension Int: _JSONInteger {}
extension Int8: _JSONInteger {}
extension Int16: _JSONInteger {}
extension Int32: _JSONInteger {}
extension Int64: _JSONInteger {}
extension UInt: _JSONInteger {}
extension UInt8: _JSONInteger {}
extension UInt16: _JSONInteger {}
extension UInt32: _JSONInteger {}
extension UInt64: _JSONInteger {}

private struct _JSONKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let impl: _JSONDecoderImpl
  let object: [String: _JSONValue]
  let codingPath: [any CodingKey]

  var allKeys: [Key] { object.keys.compactMap(Key.init(stringValue:)) }
  func contains(_ key: Key) -> Bool { object[key.stringValue] != nil }

  func decodeNil(forKey key: Key) throws -> Bool {
    if case .null = try member(key) { return true }
    return false
  }
  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    try impl.unbox(try member(key), as: type, codingPath: codingPath + [key])
  }
  func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
    guard let value = object[key.stringValue] else { return nil }
    if case .null = value { return nil }
    return try impl.unbox(value, as: type, codingPath: codingPath + [key])
  }
  func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
    try decoder(for: key).container(keyedBy: type)
  }
  func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
    try decoder(for: key).unkeyedContainer()
  }
  func superDecoder() throws -> any Decoder {
    _JSONDecoderImpl(value: object[_JSONKey.super.stringValue] ?? .null, options: impl.options, codingPath: codingPath + [_JSONKey.super])
  }
  func superDecoder(forKey key: Key) throws -> any Decoder {
    _JSONDecoderImpl(value: object[key.stringValue] ?? .null, options: impl.options, codingPath: codingPath + [key])
  }

  private func decoder(for key: Key) throws -> _JSONDecoderImpl {
    _JSONDecoderImpl(value: try member(key), options: impl.options, codingPath: codingPath + [key])
  }

  private func member(_ key: Key) throws -> _JSONValue {
    guard let value = object[key.stringValue] else {
      throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
    }
    return value
  }
}

private struct _JSONUnkeyedDecodingContainer: UnkeyedDecodingContainer {
  let impl: _JSONDecoderImpl
  let values: [_JSONValue]
  let codingPath: [any CodingKey]
  var currentIndex = 0

  init(impl: _JSONDecoderImpl, values: [_JSONValue], codingPath: [any CodingKey]) {
    self.impl = impl
    self.values = values
    self.codingPath = codingPath
  }

  var count: Int? { values.count }
  var isAtEnd: Bool { currentIndex >= values.count }

  mutating func decodeNil() throws -> Bool {
    if case .null = try next(Never.self, consume: false) {
      currentIndex += 1
      return true
    }
    return false
  }
  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let path = codingPath + [_JSONKey(index: currentIndex)]
    let value = try next(T.self, consume: true)
    return try impl.unbox(value, as: type, codingPath: path)
  }
  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
    let path = codingPath + [_JSONKey(index: currentIndex)]
    return try _JSONDecoderImpl(value: try next(KeyedDecodingContainer<NestedKey>.self, consume: true), options: impl.options, codingPath: path).container(keyedBy: type)
  }
  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    let path = codingPath + [_JSONKey(index: currentIndex)]
    return try _JSONDecoderImpl(value: try next((any UnkeyedDecodingContainer).self, consume: true), options: impl.options, codingPath: path).unkeyedContainer()
  }
  mutating func superDecoder() throws -> any Decoder {
    let path = codingPath + [_JSONKey(index: currentIndex)]
    return _JSONDecoderImpl(value: try next((any Decoder).self, consume: true), options: impl.options, codingPath: path)
  }

  private mutating func next<T>(_ type: T.Type, consume: Bool) throws -> _JSONValue {
    guard !isAtEnd else {
      throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: codingPath + [_JSONKey(index: currentIndex)], debugDescription: "Unkeyed container is at end."))
    }
    defer { if consume { currentIndex += 1 } }
    return values[currentIndex]
  }
}
#else
/// Embedded Swift cannot reference Swift.Codable/Encoder/Decoder at all.
/// Keep the familiar coder names available as a façade; typed Codable
/// synthesis is supplied by the schema bridge rather than Swift runtime
/// protocols. Until a generated schema is registered, generic operations fail
/// deterministically instead of pulling the unavailable Codable runtime in.
/// Reference types, like Foundation's: callers configure a `let` coder after creating it.
public final class JSONDecoder: @unchecked Sendable {
  public enum KeyDecodingStrategy: Sendable { case useDefaultKeys, convertFromSnakeCase }
  public enum DateDecodingStrategy: Sendable { case deferredToDate, secondsSince1970, millisecondsSince1970 }
  public var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
  public var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
  public init() {}
  public func decode<T: EmbeddedDecodable>(_ type: T.Type, from data: Data) throws -> T {
    let oldDate = EmbeddedCodableStrategies.date
    switch dateDecodingStrategy { case .deferredToDate: EmbeddedCodableStrategies.date = .deferredToDate; case .secondsSince1970: EmbeddedCodableStrategies.date = .secondsSince1970; case .millisecondsSince1970: EmbeddedCodableStrategies.date = .millisecondsSince1970 }
    defer { EmbeddedCodableStrategies.date = oldDate }
    guard keyDecodingStrategy == .convertFromSnakeCase else {
      return try _EmbeddedJSONCodec.decode(type, from: Data(data))
    }
    let tree = try _EmbeddedJSONCodec._parse(Data(data))
    return try T._embeddedDecodeJSONValue(tree._mappingKeys(_EmbeddedKeyCase.camelFromSnake))
  }
}
public final class JSONEncoder: @unchecked Sendable {
  public enum DateEncodingStrategy: Sendable { case deferredToDate, secondsSince1970, millisecondsSince1970 }
  public enum DataEncodingStrategy: Sendable { case base64, bytes }
  public enum KeyEncodingStrategy: Sendable { case useDefaultKeys, convertToSnakeCase }
  public struct OutputFormatting: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let prettyPrinted = OutputFormatting(rawValue: 1)
    public static let sortedKeys = OutputFormatting(rawValue: 2)
    public static let withoutEscapingSlashes = OutputFormatting(rawValue: 8)
  }
  public var dateEncodingStrategy: DateEncodingStrategy = .deferredToDate
  public var dataEncodingStrategy: DataEncodingStrategy = .base64
  public var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys
  /// Objects are always written with sorted keys and without whitespace; the option exists for source compatibility.
  public var outputFormatting: OutputFormatting = []
  public init() {}
  public func encode<T: EmbeddedEncodable>(_ value: T) throws -> Data {
    try encodeTree { try value._embeddedJSONValue() }
  }
  /// For call sites that hold an existential (`endpoint.jsonValue: Encodable?`); Embedded Swift cannot specialize the
  /// generic spelling on `any EmbeddedEncodable`.
  public func encode(_ value: any EmbeddedEncodable) throws -> Data {
    try encodeTree { try value._embeddedJSONValue() }
  }
  private func encodeTree(_ makeTree: () throws -> _EmbeddedJSONValue) throws -> Data {
    let oldDate=EmbeddedCodableStrategies.date, oldData=EmbeddedCodableStrategies.data
    switch dateEncodingStrategy { case .deferredToDate: EmbeddedCodableStrategies.date = .deferredToDate; case .secondsSince1970: EmbeddedCodableStrategies.date = .secondsSince1970; case .millisecondsSince1970: EmbeddedCodableStrategies.date = .millisecondsSince1970 }
    switch dataEncodingStrategy { case .base64: EmbeddedCodableStrategies.data = .base64; case .bytes: EmbeddedCodableStrategies.data = .bytes }
    defer { EmbeddedCodableStrategies.date=oldDate; EmbeddedCodableStrategies.data=oldData }
    var tree = try makeTree()
    if keyEncodingStrategy == .convertToSnakeCase { tree = tree._mappingKeys(_EmbeddedKeyCase.snakeFromCamel) }
    return Data(try _EmbeddedJSONCodec._encode(tree))
  }
}

#endif
