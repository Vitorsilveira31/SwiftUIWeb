/// The text of the extensions the Embedded Codable generator writes. The wording is the previous lowerer's, byte for
/// byte: a lowered application is compiled from it, and the golden comparison reads it.

enum CodableTemplates {
  static func rawEnum(_ qualifiedName: String, raw: String) -> String {
    "\nextension \(qualifiedName) {\n  public func _embeddedJSONValue() throws -> EmbeddedJSONValue { try rawValue._embeddedJSONValue() }\n  public static func _embeddedDecodeJSONValue(_ value: EmbeddedJSONValue) throws -> Self {\n    let raw = try \(raw)._embeddedDecodeJSONValue(value)\n    guard let result = Self(rawValue: raw) else { throw EmbeddedCodableError.typeMismatch }\n    return result\n  }\n}\n"
  }

  static func associatedEnum(_ name: String, encode: [String], decode: [String]) -> String {
    "\nextension \(name) {\n public func _embeddedJSONValue() throws -> EmbeddedJSONValue { switch self { \(encode.joined(separator: "; ")) } }\n public static func _embeddedDecodeJSONValue(_ value: EmbeddedJSONValue) throws -> Self { guard case .object(let root)=value, root.count==1, let caseName=root.keys.first, let payloadValue=root[caseName] else { throw EmbeddedCodableError.typeMismatch }; switch caseName { \(decode.joined(separator: "; ")); default: throw EmbeddedCodableError.typeMismatch } }\n}\n"
  }

  static func structure(_ qualifiedName: String, object: String, guardClause: String, arguments: String, decoderInit: String) -> String {
    "\nextension \(qualifiedName) {\n  public func _embeddedJSONValue() throws -> EmbeddedJSONValue { .object(\(object)) }\n  public static func _embeddedDecodeJSONValue(_ value: EmbeddedJSONValue) throws -> Self {\n    \(guardClause) else { throw EmbeddedCodableError.typeMismatch }\n    return Self(\(arguments))\n  }\n\(decoderInit)}\n"
  }

  static func structureWithWrittenInit(_ qualifiedName: String, object: String, guardClause: String, assignments: String, decoderInit: String) -> String {
    "\nextension \(qualifiedName) {\n  public func _embeddedJSONValue() throws -> EmbeddedJSONValue { .object(\(object)) }\n  fileprivate init(_embeddedObject object: [String: EmbeddedJSONValue]) throws {\n\(assignments)  }\n  public static func _embeddedDecodeJSONValue(_ value: EmbeddedJSONValue) throws -> Self {\n    \(guardClause) else { throw EmbeddedCodableError.typeMismatch }\n    return try Self(_embeddedObject: object)\n  }\n\(decoderInit)}\n"
  }

  static let decoderInit =
    "  public init(from decoder: EmbeddedDecoder) throws { self = try Self._embeddedDecodeJSONValue(decoder._value) }\n"

  static func codingKeyConformance(_ path: String, value: String, parse: String) -> String {
    "\nextension \(path) {\n  public var stringValue: String { switch self { \(value) } }\n  public init?(stringValue: String) { switch stringValue { \(parse); default: return nil } }\n}\n"
  }

  static func implicitCodingKeys(_ qualifiedName: String, cases: String) -> String {
    "\nextension \(qualifiedName) {\n  fileprivate enum CodingKeys: String, EmbeddedCodingKey { case \(cases) }\n}\n"
  }

  static let declaredDecoderBridge =
    "  public static func _embeddedDecodeJSONValue(_ value: EmbeddedJSONValue) throws -> Self { try Self(from: EmbeddedDecoder(value)) }\n"

  // MARK: Editing a generated extension

  /// `Optional<T>` for a trailing `T?`: `URL?._embeddedDecodeJSONValue` does not parse as a metatype expression.
  static func spellType(_ type: String) -> String {
    let trimmed = type.trimmingWhitespace()
    if trimmed.hasSuffix("?") {
      return "Optional<\(spellType(String(trimmed.dropLast())))>"
    }
    return trimmed
  }

  /// Removes the function of a generated extension that the type did not ask for. `signature` starts the function;
  /// its body is cut by brace matching.
  static func dropFunction(_ text: String, signature: String) -> String {
    let bytes = Array(text.utf8)
    guard let start = find(Array(signature.utf8), in: bytes, from: 0),
      let open = bytes[start...].firstIndex(of: UInt8(ascii: "{")),
      let close = matchingBrace(bytes, open: open)
    else { return text }
    var lineStart = start
    while lineStart > 0 && bytes[lineStart - 1] != 0x0A { lineStart -= 1 }
    var end = close + 1
    if end < bytes.count && bytes[end] == 0x0A { end += 1 }
    return String(decoding: bytes[..<lineStart] + bytes[end...], as: UTF8.self)
  }

  static func keepRequestedHalves(_ text: String, encode: Bool, decode: Bool) -> String {
    var result = text
    if !encode {
      result = dropFunction(result, signature: "public func _embeddedJSONValue()")
    }
    if !decode {
      result = dropFunction(result, signature: "public static func _embeddedDecodeJSONValue(")
      result = dropFunction(result, signature: "public init(from decoder: EmbeddedDecoder)")
      result = dropFunction(result, signature: "fileprivate init(_embeddedObject object:")
    }
    return result
  }

  /// Replaces the generated decode function with a call to the type's own `init(from:)`, and drops the synthesized
  /// initializer it would collide with.
  static func useDeclaredDecoderInit(_ text: String) -> String {
    var result = dropFunction(text, signature: "public static func _embeddedDecodeJSONValue(")
    result = dropFunction(result, signature: "public init(from decoder: EmbeddedDecoder)")
    var bytes = Array(result.utf8)
    guard let close = bytes.lastIndex(of: UInt8(ascii: "}")) else { return result }
    bytes.insert(contentsOf: Array(declaredDecoderBridge.utf8), at: close)
    return String(decoding: bytes, as: UTF8.self)
  }

  private static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
    guard !needle.isEmpty, bytes.count >= needle.count else { return nil }
    var index = start
    while index <= bytes.count - needle.count {
      if bytes[index] == needle[0] && bytes[index..<index + needle.count].elementsEqual(needle) { return index }
      index += 1
    }
    return nil
  }

  /// The closing brace that matches the one at `open`; generated text holds only simple string literals.
  private static func matchingBrace(_ bytes: [UInt8], open: Int) -> Int? {
    var depth = 0
    var index = open
    while index < bytes.count {
      switch bytes[index] {
      case UInt8(ascii: "\""):
        index += 1
        while index < bytes.count && bytes[index] != UInt8(ascii: "\"") {
          if bytes[index] == UInt8(ascii: "\\") { index += 1 }
          index += 1
        }
      case UInt8(ascii: "{"):
        depth += 1
      case UInt8(ascii: "}"):
        depth -= 1
        if depth == 0 { return index }
      default:
        break
      }
      index += 1
    }
    return nil
  }
}

extension String {
  func trimmingWhitespace() -> String {
    var scalars = Substring(self).unicodeScalars[...]
    while let first = scalars.first, first.properties.isWhitespace { scalars.removeFirst() }
    while let last = scalars.last, last.properties.isWhitespace { scalars.removeLast() }
    return String(String.UnicodeScalarView(scalars))
  }
}
