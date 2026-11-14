@_spi(Renderer) import SwiftUIWebLocking

public enum _EmbeddedCodableError: Error, Sendable {
  case invalidJSON
  case typeMismatch
  case missingKey(String)
  case invalidNumber
}

public indirect enum _EmbeddedJSONValue: Sendable {
  case null, bool(Bool), number(Double), string(String), array([_EmbeddedJSONValue]), object([String: _EmbeddedJSONValue])

  public subscript(_ key: String) -> _EmbeddedJSONValue? {
    guard case .object(let values) = self else { return nil }
    return values[key]
  }
}

/// Reads and writes strict JSON: RFC 8259 grammar, valid UTF-8, no non-finite numbers, at most 127 nested containers. Objects are written compact with their keys
/// in UTF-8 byte order and numbers as the shortest text that reads back to the same `Double`.
public enum _EmbeddedJSONCodec {

  /// Parses bytes into the JSON tree without decoding a type, so a coder strategy can rewrite it first.
  @_spi(Renderer) public static func _parse(_ data: Data) throws -> _EmbeddedJSONValue {
    var parser = Parser(Array(data))
    let value = try parser.value()
    parser.ws()
    guard parser.i == parser.b.count else { throw _EmbeddedCodableError.invalidJSON }
    return value
  }
  @_spi(Renderer) public static func _encode(_ value: _EmbeddedJSONValue) throws -> Data {
    var output: [UInt8] = []
    try write(value, to: &output)
    return Data(output)
  }

  static func write(_ value: _EmbeddedJSONValue, to output: inout [UInt8]) throws {
    switch value {
    case .null: output.append(contentsOf: "null".utf8)
    case .bool(let v): output.append(contentsOf: (v ? "true" : "false").utf8)
    case .number(let v):
      guard v.isFinite else { throw _EmbeddedCodableError.invalidNumber }
      writeNumber(v, to: &output)
    case .string(let v): quote(v, to: &output)
    case .array(let values):
      output.append(91)
      for (index, value) in values.enumerated() {
        if index > 0 { output.append(44) }
        try write(value, to: &output)
      }
      output.append(93)
    case .object(let values):
      output.append(123)
      for (index, entry) in values.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }).enumerated() {
        if index > 0 { output.append(44) }
        quote(entry.key, to: &output)
        output.append(58)
        try write(entry.value, to: &output)
      }
      output.append(125)
    }
  }

  /// Integers (below 2^63) are written as digits. Other values take the shortest digits that read back exactly, laid out
  /// as the Ryu algorithm does: plain from 1e-5 up to 1e16 (`0.00001`, `1234.5`), otherwise `1.234e-7` / `1e30`.
  static func writeNumber(_ value: Double, to output: inout [UInt8]) {
    if value.rounded(.towardZero) == value && value.magnitude < 0x1p63 { output.append(contentsOf: String(Int64(value)).utf8); return }
    if value < 0 { output.append(45) }
    var digits: [UInt8] = []
    var point: Int?
    var exponent = 0, negativeExponent = false, inExponent = false
    for byte in String(value.magnitude).utf8 {
      switch byte {
      case 46: point = digits.count
      case 101: inExponent = true
      case 45: negativeExponent = true
      case 43: break
      default: if inExponent { exponent = exponent * 10 + Int(byte - 48) } else { digits.append(byte) }
      }
    }
    // The value is 0.<digits> * 10^position.
    var position = (point ?? digits.count) + (negativeExponent ? -exponent : exponent)
    let leadingZeros = digits.prefix(while: { $0 == 48 }).count
    position -= leadingZeros
    digits.removeFirst(leadingZeros)
    while digits.last == 48 { digits.removeLast() }
    if position > 0 && position <= 16 {
      if digits.count <= position {
        output.append(contentsOf: digits)
        output.append(contentsOf: repeatElement(48, count: position - digits.count))
        output.append(contentsOf: [46, 48])
      } else {
        output.append(contentsOf: digits[..<position])
        output.append(46)
        output.append(contentsOf: digits[position...])
      }
    } else if position > -5 && position <= 0 {
      output.append(contentsOf: [48, 46])
      output.append(contentsOf: repeatElement(48, count: -position))
      output.append(contentsOf: digits)
    } else {
      output.append(digits[0])
      if digits.count > 1 { output.append(46); output.append(contentsOf: digits[1...]) }
      output.append(101)
      output.append(contentsOf: String(position - 1).utf8)
    }
  }

  static func quote(_ string: String, to output: inout [UInt8]) {
    output.append(34)
    let hex = Array("0123456789abcdef".utf8)
    for byte in string.utf8 {
      switch byte {
      case 34: output.append(contentsOf: [92, 34])
      case 92: output.append(contentsOf: [92, 92])
      case 8: output.append(contentsOf: [92, 98])
      case 9: output.append(contentsOf: [92, 116])
      case 10: output.append(contentsOf: [92, 110])
      case 12: output.append(contentsOf: [92, 102])
      case 13: output.append(contentsOf: [92, 114])
      case 0..<32:
        output.append(contentsOf: [92, 117, 48, 48, hex[Int(byte >> 4)], hex[Int(byte & 15)]])
      default: output.append(byte)
      }
    }
    output.append(34)
  }

  struct Parser {
    let b: [UInt8]
    var i = 0
    var depth = 0
    init(_ b: [UInt8]) { self.b = b }
    /// The byte at the cursor, or 0 past the end (0 is never valid where a caller looks for a specific byte).
    var peek: UInt8 { i < b.count ? b[i] : 0 }
    var peekIsDigit: Bool { peek >= 48 && peek <= 57 }

    mutating func ws() { while i < b.count && (b[i] == 32 || b[i] == 10 || b[i] == 13 || b[i] == 9) { i += 1 } }
    /// One JSON value. Nested containers are kept on explicit stacks rather than the call stack, so the nesting a
    /// document may have does not depend on how large the frames of a build are (a debug build in a Web Worker has a
    /// small stack). A value is added to the innermost container in place (`arrays[last].append`), never to a copy taken
    /// out of the stack, so a long array or object is read in linear time.
    mutating func value() throws -> _EmbeddedJSONValue {
      var openIsArray: [Bool] = []  // the open containers, innermost last: true for an array, false for an object
      var arrays: [[_EmbeddedJSONValue]] = []
      var objects: [[String: _EmbeddedJSONValue]] = []
      var keys: [String] = []  // for each open object, the key of the value being read
      reading: while true {
        ws()
        var finished: _EmbeddedJSONValue
        switch peek {
        case 110: finished = try literal("null", .null)
        case 116: finished = try literal("true", .bool(true))
        case 102: finished = try literal("false", .bool(false))
        case 34: finished = .string(try string())
        case 45, 48...57: finished = try number()
        case 91:
          try enter()
          i += 1
          ws()
          guard peek == 93 else {
            openIsArray.append(true)
            arrays.append([])
            continue reading
          }
          i += 1
          depth -= 1
          finished = .array([])
        case 123:
          try enter()
          i += 1
          ws()
          guard peek == 125 else {
            openIsArray.append(false)
            objects.append([:])
            keys.append(try objectKey())
            continue reading
          }
          i += 1
          depth -= 1
          finished = .object([:])
        default: throw _EmbeddedCodableError.invalidJSON
        }
        // Hand the value to the innermost open container; a container that ends here becomes the value for the next one.
        while let isArray = openIsArray.last {
          ws()
          if isArray {
            arrays[arrays.count - 1].append(finished)
            if peek == 44 {
              i += 1
              continue reading
            }
            guard peek == 93 else { throw _EmbeddedCodableError.invalidJSON }
            i += 1
            depth -= 1
            openIsArray.removeLast()
            finished = .array(arrays.removeLast())
          } else {
            objects[objects.count - 1][keys.removeLast()] = finished
            if peek == 44 {
              i += 1
              keys.append(try objectKey())
              continue reading
            }
            guard peek == 125 else { throw _EmbeddedCodableError.invalidJSON }
            i += 1
            depth -= 1
            openIsArray.removeLast()
            finished = .object(objects.removeLast())
          }
        }
        return finished
      }
    }

    /// An object's `"key":`, up to the value.
    mutating func objectKey() throws -> String {
      ws()
      guard peek == 34 else { throw _EmbeddedCodableError.invalidJSON }
      let key = try string()
      ws()
      guard peek == 58 else { throw _EmbeddedCodableError.invalidJSON }
      i += 1
      return key
    }
    mutating func literal(_ text: String, _ result: _EmbeddedJSONValue) throws -> _EmbeddedJSONValue {
      for byte in text.utf8 {
        guard peek == byte else { throw _EmbeddedCodableError.invalidJSON }
        i += 1
      }
      return result
    }
    /// A 128th nested array or object is refused, the limit common JSON parsers keep.
    mutating func enter() throws {
      depth += 1
      guard depth < 128 else { throw _EmbeddedCodableError.invalidJSON }
    }
    mutating func string() throws -> String {
      i += 1
      let start = i
      while i < b.count && b[i] >= 32 && b[i] < 128 && b[i] != 34 && b[i] != 92 { i += 1 }
      if peek == 34 {
        i += 1
        return String(decoding: b[start..<(i - 1)], as: UTF8.self)
      }
      var output = Array(b[start..<i])
      var nonASCII = false
      while i < b.count {
        let byte = b[i]
        i += 1
        if byte == 34 {
          // Decoding repairs invalid UTF-8, so different bytes mean the input was not valid.
          let string = String(decoding: output, as: UTF8.self)
          guard !nonASCII || string.utf8.elementsEqual(output) else { throw _EmbeddedCodableError.invalidJSON }
          return string
        }
        if byte == 92 {
          try escape(into: &output)
        } else {
          guard byte >= 32 else { throw _EmbeddedCodableError.invalidJSON }
          if byte >= 128 { nonASCII = true }
          output.append(byte)
        }
      }
      throw _EmbeddedCodableError.invalidJSON
    }
    mutating func escape(into output: inout [UInt8]) throws {
      let escaped = peek
      i += 1
      switch escaped {
      case 34, 92, 47: output.append(escaped)
      case 98: output.append(8)
      case 102: output.append(12)
      case 110: output.append(10)
      case 114: output.append(13)
      case 116: output.append(9)
      case 117:
        let first = try unicodeCodeUnit()
        var scalarValue = UInt32(first)
        if (0xD800...0xDBFF).contains(first) {
          guard peek == 92, i + 1 < b.count, b[i + 1] == 117 else { throw _EmbeddedCodableError.invalidJSON }
          i += 2
          let second = try unicodeCodeUnit()
          guard (0xDC00...0xDFFF).contains(second) else { throw _EmbeddedCodableError.invalidJSON }
          scalarValue = 0x10000 + ((UInt32(first) - 0xD800) << 10) + (UInt32(second) - 0xDC00)
        } else if (0xDC00...0xDFFF).contains(first) {
          throw _EmbeddedCodableError.invalidJSON
        }
        guard let scalar = UnicodeScalar(scalarValue) else { throw _EmbeddedCodableError.invalidJSON }
        output.append(contentsOf: String(scalar).utf8)
      default: throw _EmbeddedCodableError.invalidJSON
      }
    }
    mutating func unicodeCodeUnit() throws -> UInt16 {
      guard i + 4 <= b.count else { throw _EmbeddedCodableError.invalidJSON }
      var value: UInt16 = 0
      for _ in 0..<4 {
        let byte = b[i]
        i += 1
        let digit: UInt16
        switch byte {
        case 48...57: digit = UInt16(byte - 48)
        case 65...70: digit = UInt16(byte - 65 + 10)
        case 97...102: digit = UInt16(byte - 97 + 10)
        default: throw _EmbeddedCodableError.invalidJSON
        }
        value = value * 16 + digit
      }
      return value
    }
    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`, finite. Up to 15 digits with a small exponent are exact in
    /// a `Double`, so one multiplication or division rounds correctly; anything else goes through `Double(String)`.
    mutating func number() throws -> _EmbeddedJSONValue {
      let start = i
      let negative = peek == 45
      if negative { i += 1 }
      var mantissa: UInt64 = 0
      var taken = 0, exponent = 0
      guard peekIsDigit else { throw _EmbeddedCodableError.invalidJSON }
      if peek == 48 {
        i += 1
      } else {
        while peekIsDigit { take(&mantissa, &taken) }
      }
      if peek == 46 {
        i += 1
        guard peekIsDigit else { throw _EmbeddedCodableError.invalidJSON }
        while peekIsDigit { take(&mantissa, &taken); exponent -= 1 }
      }
      if peek == 101 || peek == 69 {
        i += 1
        let negativeExponent = peek == 45
        if peek == 43 || peek == 45 { i += 1 }
        guard peekIsDigit else { throw _EmbeddedCodableError.invalidJSON }
        var written = 0
        while peekIsDigit { written = min(written * 10 + Int(peek - 48), 100_000); i += 1 }
        exponent += negativeExponent ? -written : written
      }
      if taken <= 15 && exponent >= -22 && exponent <= 22 {
        var power = 1.0
        for _ in 0..<exponent.magnitude { power *= 10 }
        let value = exponent < 0 ? Double(mantissa) / power : Double(mantissa) * power
        return .number(negative ? -value : value)
      }
      guard let value = Double(String(decoding: b[start..<i], as: UTF8.self)), value.isFinite else { throw _EmbeddedCodableError.invalidJSON }
      return .number(value)
    }
    /// Consumes one digit. The mantissa only matters while it has at most 15 digits.
    mutating func take(_ mantissa: inout UInt64, _ taken: inout Int) {
      if taken < 19 { mantissa = mantissa * 10 + UInt64(peek - 48) }
      taken += 1
      i += 1
    }
  }
}

public extension _EmbeddedJSONValue {
  /// The tree with every object key rewritten by `transform` (JSONDecoder/JSONEncoder key strategies).
  func _mappingKeys(_ transform: (String) -> String) -> _EmbeddedJSONValue {
    switch self {
    case .array(let values): return .array(values.map { $0._mappingKeys(transform) })
    case .object(let object):
      var result: [String: _EmbeddedJSONValue] = [:]
      for (key, value) in object { result[transform(key)] = value._mappingKeys(transform) }
      return .object(result)
    default: return self
    }
  }
}

/// Foundation's `convertFromSnakeCase` / `convertToSnakeCase` key rules.
public enum _EmbeddedKeyCase {
  public static func camelFromSnake(_ key: String) -> String {
    guard key.contains("_") else { return key }
    let chars = Array(key)
    var start = 0
    while start < chars.count, chars[start] == "_" { start += 1 }
    var end = chars.count
    while end > start, chars[end - 1] == "_" { end -= 1 }
    guard start < end else { return key }
    let words = String(chars[start..<end]).split(separator: "_", omittingEmptySubsequences: true)
    // Foundation's algorithm: one word stays as written; otherwise the first is lowercased and the rest capitalized.
    guard words.count > 1 else { return key }
    var result = String(chars[..<start]) + words[0].lowercased()
    for word in words.dropFirst() {
      result += _capitalizedKeyWord(word)
    }
    return result + String(chars[end...])
  }

  /// One word of a snake_case key, capitalized the way Foundation's `capitalized` does: a letter that starts a word
  /// (the first character, or one after a non-letter) is uppercased and the other letters are lowercased. So `2m`
  /// becomes `2M`, which is how `temperature_2m` maps to `temperature2M`.
  private static func _capitalizedKeyWord(_ word: Substring) -> String {
    var result = ""
    var afterLetter = false
    for character in word {
      if character.isLetter {
        result += afterLetter ? String(character).lowercased() : String(character).uppercased()
        afterLetter = true
      } else {
        result.append(character)
        afterLetter = false
      }
    }
    return result
  }

  public static func snakeFromCamel(_ key: String) -> String {
    let chars = Array(key)
    var result = ""
    for (index, char) in chars.enumerated() {
      if char.isUppercase {
        let previousLower = index > 0 && (chars[index - 1].isLowercase || chars[index - 1].isNumber)
        let acronymEnd = index > 0 && chars[index - 1].isUppercase && index + 1 < chars.count && chars[index + 1].isLowercase
        if previousLower || acronymEnd { result += "_" }
        result += String(char).lowercased()
      } else {
        result.append(char)
      }
    }
    return result
  }
}

public extension _EmbeddedJSONValue {
  static func required(_ object: [String: _EmbeddedJSONValue], _ key: String) throws -> _EmbeddedJSONValue {
    guard let value = object[key] else { throw _EmbeddedCodableError.missingKey(key) }; return value
  }
}

private let _embeddedBase64Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
public func _embeddedBase64Encode(_ bytes: [UInt8]) -> String {
  var out:[UInt8]=[]; var i=0
  while i < bytes.count {
    let a=UInt32(bytes[i]); let b:UInt32=i+1<bytes.count ? UInt32(bytes[i+1]) : 0; let c:UInt32=i+2<bytes.count ? UInt32(bytes[i+2]) : 0; let n=(a<<16)|(b<<8)|c
    out.append(_embeddedBase64Alphabet[Int((n>>18)&63)]); out.append(_embeddedBase64Alphabet[Int((n>>12)&63)])
    out.append(i+1<bytes.count ? _embeddedBase64Alphabet[Int((n>>6)&63)] : 61); out.append(i+2<bytes.count ? _embeddedBase64Alphabet[Int(n&63)] : 61); i += 3
  }
  return String(decoding: out, as: UTF8.self)
}
public func _embeddedBase64Decode(_ string:String) throws -> [UInt8] {
  func v(_ c:UInt8)->Int { if c>=65&&c<=90{return Int(c-65)};if c>=97&&c<=122{return Int(c-97+26)};if c>=48&&c<=57{return Int(c-48+52)};if c==43{return 62};if c==47{return 63};return -1 }
  let x=Array(string.utf8); guard x.count % 4 == 0 else { throw _EmbeddedCodableError.invalidJSON }; var out:[UInt8]=[]; var i=0
  while i<x.count { let a=v(x[i]),b=v(x[i+1]),c=x[i+2]==61 ? 0:v(x[i+2]),d=x[i+3]==61 ? 0:v(x[i+3]); guard a>=0&&b>=0&&c>=0&&d>=0 else{throw _EmbeddedCodableError.invalidJSON};let n=(a<<18)|(b<<12)|(c<<6)|d;out.append(UInt8((n>>16)&255));if x[i+2] != 61{out.append(UInt8((n>>8)&255))};if x[i+3] != 61{out.append(UInt8(n&255))};i+=4 }; return out
}

#if hasFeature(Embedded) || EMBEDDED_JSON_TESTS
// The Codable stand-in Embedded builds use. Natively Swift's Codable and the framework's JSONEncoder/JSONDecoder are the
// only coding API, so these spellings exist only where lowered code needs them.
public typealias EmbeddedCodableError = _EmbeddedCodableError
public typealias EmbeddedJSONValue = _EmbeddedJSONValue
public typealias EmbeddedJSONCodec = _EmbeddedJSONCodec
public typealias EmbeddedKeyCase = _EmbeddedKeyCase

/// Decodes one field of a synthesized initializer; a failure names the field it came from.
public func _embeddedField<T: EmbeddedDecodable>(_ type: T.Type, _ object: [String: _EmbeddedJSONValue], _ key: String) throws -> T {
  try T._embeddedDecodeJSONValue(object[key] ?? .null)
}

/// Compile-time serialization contract used only after Embedded source lowering.
/// It intentionally does not depend on Swift.Codable, which the Embedded stdlib marks unavailable.
/// The two halves mirror `Encodable` and `Decodable`: a type that is only decoded
/// (a backend response) or only encoded (a request body) carries only that half,
/// so the other never becomes code.
public protocol EmbeddedEncodable {
  func _embeddedJSONValue() throws -> _EmbeddedJSONValue
}
public protocol EmbeddedDecodable {
  static func _embeddedDecodeJSONValue(_ value: _EmbeddedJSONValue) throws -> Self
}
public typealias EmbeddedCodable = EmbeddedEncodable & EmbeddedDecodable

public extension _EmbeddedJSONCodec {
  static func encode<T: EmbeddedEncodable>(_ value: T) throws -> Data {
    try _encode(value._embeddedJSONValue())
  }
  static func decode<T: EmbeddedDecodable>(_ type: T.Type, from data: Data) throws -> T {
    try T._embeddedDecodeJSONValue(_parse(data))
  }
}

/// The number as `T` when it is an integer that `T` can hold. A fraction, a non-finite value or an out-of-range value is refused;
/// `T(Double)` trapped on the last two and truncated the first.
private func _embeddedInteger<T: FixedWidthInteger>(_ x: Double, _ type: T.Type) throws -> T {
  guard let value = T(exactly: x) else { throw _EmbeddedCodableError.invalidNumber }
  return value
}

extension String: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.string(self)}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->String{guard case .string(let x)=v else{throw _EmbeddedCodableError.typeMismatch};return x} }
extension Bool: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.bool(self)}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Bool{guard case .bool(let x)=v else{throw _EmbeddedCodableError.typeMismatch};return x} }
extension Int: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Int{guard case .number(let x)=v else{throw _EmbeddedCodableError.typeMismatch};return try _embeddedInteger(x, Int.self)} }
extension Int8: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Int8{guard case .number(let x)=v else{throw _EmbeddedCodableError.typeMismatch};return try _embeddedInteger(x, Int8.self)} }
extension Int16: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Int16{guard case .number(let x)=v else{throw _EmbeddedCodableError.typeMismatch};return try _embeddedInteger(x, Int16.self)} }
extension UInt: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->UInt{guard case .number(let x)=v,x>=0 else{throw _EmbeddedCodableError.typeMismatch};return try _embeddedInteger(x, UInt.self)} }
extension UInt8: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->UInt8{guard case .number(let x)=v,x>=0 else{throw _EmbeddedCodableError.typeMismatch};return try _embeddedInteger(x, UInt8.self)} }
extension UInt16: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->UInt16{guard case .number(let x)=v,x>=0 else{throw _EmbeddedCodableError.typeMismatch};return try _embeddedInteger(x, UInt16.self)} }
extension UInt32: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->UInt32{guard case .number(let x)=v,x>=0 else{throw _EmbeddedCodableError.typeMismatch};return try _embeddedInteger(x, UInt32.self)} }
extension UInt64: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->UInt64{guard case .number(let x)=v,x>=0 else{throw _EmbeddedCodableError.typeMismatch};return try _embeddedInteger(x, UInt64.self)} }
extension Int32: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Int32{guard case .number(let x)=v else{throw _EmbeddedCodableError.typeMismatch};return try _embeddedInteger(x, Int32.self)} }
extension Int64: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Int64{guard case .number(let x)=v else{throw _EmbeddedCodableError.typeMismatch};return try _embeddedInteger(x, Int64.self)} }
extension Double: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(self)}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Double{guard case .number(let x)=v else{throw _EmbeddedCodableError.typeMismatch};return x} }
extension Float: EmbeddedCodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{.number(Double(self))}; public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Float{guard case .number(let x)=v else{throw _EmbeddedCodableError.typeMismatch};return Float(x)} }
extension Optional: EmbeddedEncodable where Wrapped: EmbeddedEncodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{switch self{case .none:return .null;case .some(let x):return try x._embeddedJSONValue()}} }
extension Optional: EmbeddedDecodable where Wrapped: EmbeddedDecodable { public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Self{if case .null=v{return nil};return try Wrapped._embeddedDecodeJSONValue(v)} }
extension Array: EmbeddedEncodable where Element: EmbeddedEncodable {
  public func _embeddedJSONValue() throws -> _EmbeddedJSONValue { var r:[_EmbeddedJSONValue]=[]; for x in self { r.append(try x._embeddedJSONValue()) }; return .array(r) }
}
extension Array: EmbeddedDecodable where Element: EmbeddedDecodable {
  public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Self { guard case .array(let a)=v else{throw _EmbeddedCodableError.typeMismatch}; var r:Self=[]; for x in a { r.append(try Element._embeddedDecodeJSONValue(x)) }; return r }
}
extension Dictionary: EmbeddedEncodable where Key == String, Value: EmbeddedEncodable { public func _embeddedJSONValue() throws -> _EmbeddedJSONValue{var o:[String:_EmbeddedJSONValue]=[:];for(k,v)in self{o[k]=try v._embeddedJSONValue()};return .object(o)} }
extension Dictionary: EmbeddedDecodable where Key == String, Value: EmbeddedDecodable { public static func _embeddedDecodeJSONValue(_ v:_EmbeddedJSONValue)throws->Self{guard case .object(let o)=v else{throw _EmbeddedCodableError.typeMismatch};var r:Self=[:];for(k,x)in o{r[k]=try Value._embeddedDecodeJSONValue(x)};return r} }

// Foundation-free Codable parity primitives used by generated Embedded lowering.
public enum EmbeddedDateStrategy: Sendable { case deferredToDate, secondsSince1970, millisecondsSince1970 }
public enum EmbeddedDataStrategy: Sendable { case base64, bytes }
public enum EmbeddedCodableStrategies {
  private static let current = _Locked((date: EmbeddedDateStrategy.deferredToDate, data: EmbeddedDataStrategy.base64))
  public static var date: EmbeddedDateStrategy {
    get { current.withLock { $0.date } }
    set { current.withLock { $0.date = newValue } }
  }
  public static var data: EmbeddedDataStrategy {
    get { current.withLock { $0.data } }
    set { current.withLock { $0.data = newValue } }
  }
}

extension Data: EmbeddedCodable {
  public func _embeddedJSONValue() throws -> _EmbeddedJSONValue {
    switch EmbeddedCodableStrategies.data { case .base64: return .string(_embeddedBase64Encode(Array(self))); case .bytes: return .array(Array(self).map { .number(Double($0)) }) }
  }
  public static func _embeddedDecodeJSONValue(_ value:_EmbeddedJSONValue)throws->Data { switch value { case .string(let s): return Data(try _embeddedBase64Decode(s)); case .array(let a): var b:[UInt8]=[]; for x in a { guard case .number(let n)=x else { throw _EmbeddedCodableError.typeMismatch }; b.append(try _embeddedInteger(n, UInt8.self)) }; return Data(b); default: throw _EmbeddedCodableError.typeMismatch } }
}
#endif
