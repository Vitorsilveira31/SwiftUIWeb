/// A Foundation-free JSON tree shared by native and Embedded applications.
///
/// The native implementation conforms to Swift's `Codable` protocols. The
/// Embedded implementation conforms to SwiftUIWeb's `EmbeddedCodable` contract
/// instead; the public shape remains identical to application code on both runtimes.
#if hasFeature(Embedded)
package indirect enum JSONValue: Hashable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null
}

extension JSONValue: EmbeddedCodable {
  package func _embeddedJSONValue() throws -> _EmbeddedJSONValue {
    switch self {
    case .string(let value): return .string(value)
    case .number(let value): return .number(value)
    case .bool(let value): return .bool(value)
    case .object(let value):
      var object: [String: _EmbeddedJSONValue] = .init()
      for (key, value) in value { object[key] = try value._embeddedJSONValue() }
      return .object(object)
    case .array(let value): return .array(try value.map { try $0._embeddedJSONValue() })
    case .null: return .null
    }
  }

  package static func _embeddedDecodeJSONValue(_ value: _EmbeddedJSONValue) throws -> JSONValue {
    switch value {
    case .string(let value): return .string(value)
    case .number(let value): return .number(value)
    case .bool(let value): return .bool(value)
    case .object(let value):
      var object: [String: JSONValue] = .init()
      for (key, value) in value { object[key] = try JSONValue._embeddedDecodeJSONValue(value) }
      return .object(object)
    case .array(let value): return .array(try value.map { try JSONValue._embeddedDecodeJSONValue($0) })
    case .null: return .null
    }
  }
}
#else
package indirect enum JSONValue: Codable, Hashable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  package init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() { self = .null; return }
    if let value = try? container.decode(Bool.self) { self = .bool(value); return }
    if let value = try? container.decode(Double.self) { self = .number(value); return }
    if let value = try? container.decode(String.self) { self = .string(value); return }
    if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
    if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}
#endif
