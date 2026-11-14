#if hasFeature(Embedded)
/// Foundation-free `Decoder` shapes for hand-written `init(from:)` on Embedded.
///
/// The Embedded stdlib marks `Decoder`, `CodingKey`, and the decoding containers
/// unavailable. The source lowerer renames those spellings to the `Embedded*`
/// types below, so application code stays identical to its Foundation form
/// (`decoder.container(keyedBy:)`, `decode`, `decodeIfPresent`, nested
/// containers, `singleValueContainer`). The decoder is a thin view over the
/// already-parsed `_EmbeddedJSONValue`; it adds no parser and no existential.
/// Unkeyed containers, `superDecoder`, and custom `encode(to:)` are not covered.

public protocol EmbeddedCodingKey {
  var stringValue: String { get }
  init?(stringValue: String)
}

extension EmbeddedCodingKey where Self: RawRepresentable, Self.RawValue == String {
  public var stringValue: String { rawValue }
  public init?(stringValue: String) { self.init(rawValue: stringValue) }
}

public struct EmbeddedDecoder {
  public let _value: _EmbeddedJSONValue
  public init(_ value: _EmbeddedJSONValue) { _value = value }

  public func container<Key: EmbeddedCodingKey>(keyedBy type: Key.Type) throws -> EmbeddedKeyedDecodingContainer<Key> {
    guard case .object(let object) = _value else { throw _EmbeddedCodableError.typeMismatch }
    return EmbeddedKeyedDecodingContainer<Key>(object)
  }

  public func singleValueContainer() throws -> EmbeddedSingleValueDecodingContainer {
    EmbeddedSingleValueDecodingContainer(_value)
  }
}

public struct EmbeddedSingleValueDecodingContainer {
  let value: _EmbeddedJSONValue
  init(_ value: _EmbeddedJSONValue) { self.value = value }
  public func decodeNil() -> Bool { if case .null = value { return true }; return false }
  public func decode<T: EmbeddedDecodable>(_ type: T.Type) throws -> T { try _embeddedDecodeValue(T.self, value) }
}

/// Decodes one value, reporting a shape mismatch the way `DecodingError.typeMismatch` does so that
/// `catch DecodingError.typeMismatch` in hand-written initializers still matches.
func _embeddedDecodeValue<T: EmbeddedDecodable>(_ type: T.Type, _ value: _EmbeddedJSONValue) throws -> T {
  do { return try T._embeddedDecodeJSONValue(value) } catch _EmbeddedCodableError.typeMismatch {
    throw EmbeddedDecodingError.typeMismatch("\(T.self)")
  }
}

public struct EmbeddedKeyedDecodingContainer<Key: EmbeddedCodingKey> {
  let object: [String: _EmbeddedJSONValue]
  init(_ object: [String: _EmbeddedJSONValue]) { self.object = object }

  public var allKeys: [Key] {
    var keys: [Key] = []
    for name in object.keys.sorted() { if let key = Key(stringValue: name) { keys.append(key) } }
    return keys
  }
  public func contains(_ key: Key) -> Bool { object[key.stringValue] != nil }
  public func decodeNil(forKey key: Key) throws -> Bool {
    guard let value = object[key.stringValue] else { throw _EmbeddedCodableError.missingKey(key.stringValue) }
    if case .null = value { return true }
    return false
  }
  public func decode<T: EmbeddedDecodable>(_ type: T.Type, forKey key: Key) throws -> T {
    guard let value = object[key.stringValue] else { throw EmbeddedDecodingError.keyNotFound(key.stringValue) }
    return try _embeddedDecodeValue(T.self, value)
  }
  public func decodeIfPresent<T: EmbeddedDecodable>(_ type: T.Type, forKey key: Key) throws -> T? {
    guard let value = object[key.stringValue] else { return nil }
    if case .null = value { return nil }
    return try _embeddedDecodeValue(T.self, value)
  }
  public func nestedContainer<NestedKey: EmbeddedCodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> EmbeddedKeyedDecodingContainer<NestedKey> {
    guard let value = object[key.stringValue] else { throw _EmbeddedCodableError.missingKey(key.stringValue) }
    return try EmbeddedDecoder(value).container(keyedBy: type)
  }
  public var codingPath: [EmbeddedAnyCodingKey] { [] }
  public func nestedUnkeyedContainer(forKey key: Key) throws -> EmbeddedUnkeyedDecodingContainer {
    guard let value = object[key.stringValue] else { throw _EmbeddedCodableError.missingKey(key.stringValue) }
    guard case .array(let items) = value else { throw _EmbeddedCodableError.typeMismatch }
    return EmbeddedUnkeyedDecodingContainer(items)
  }
  public func superDecoder(forKey key: Key) throws -> EmbeddedDecoder {
    guard let value = object[key.stringValue] else { throw _EmbeddedCodableError.missingKey(key.stringValue) }
    return EmbeddedDecoder(value)
  }
}

public struct EmbeddedAnyCodingKey: EmbeddedCodingKey, Sendable {
  public var stringValue: String
  public init?(stringValue: String) { self.stringValue = stringValue }
}

/// Positional reader over a JSON array, matching `UnkeyedDecodingContainer`'s sequential `decode`.
public struct EmbeddedUnkeyedDecodingContainer {
  let items: [_EmbeddedJSONValue]
  public private(set) var currentIndex: Int = 0
  init(_ items: [_EmbeddedJSONValue]) { self.items = items }
  public var count: Int? { items.count }
  public var isAtEnd: Bool { currentIndex >= items.count }
  public var codingPath: [EmbeddedAnyCodingKey] { [] }
  public mutating func decodeNil() throws -> Bool {
    guard currentIndex < items.count else { throw EmbeddedDecodingError.valueNotFound("unkeyed") }
    if case .null = items[currentIndex] { currentIndex += 1; return true }
    return false
  }
  public mutating func decode<T: EmbeddedDecodable>(_ type: T.Type) throws -> T {
    guard currentIndex < items.count else { throw EmbeddedDecodingError.valueNotFound("unkeyed") }
    let value = items[currentIndex]
    currentIndex += 1
    return try _embeddedDecodeValue(T.self, value)
  }
  public mutating func decodeIfPresent<T: EmbeddedDecodable>(_ type: T.Type) throws -> T? {
    guard currentIndex < items.count else { return nil }
    if case .null = items[currentIndex] { currentIndex += 1; return nil }
    return try decode(T.self)
  }
}

/// Stand-in for `DecodingError`: the lowerer renames the type, so `catch DecodingError.keyNotFound` and
/// `DecodingError.dataCorruptedError(...)` in hand-written decoders keep their shape.
public enum EmbeddedDecodingError: Error, Sendable {
  case keyNotFound(String)
  case typeMismatch(String)
  case valueNotFound(String)
  case dataCorrupted(String)

  public struct Context: Sendable {
    public var codingPath: [EmbeddedAnyCodingKey]
    public var debugDescription: String
    public init(codingPath: [EmbeddedAnyCodingKey], debugDescription: String, underlyingError: EmbeddedDecodingError? = nil) {
      self.codingPath = codingPath
      self.debugDescription = debugDescription
    }
  }
  public static func dataCorrupted(_ context: Context) -> EmbeddedDecodingError { .dataCorrupted(context.debugDescription) }

  public var debugDescription: String {
    switch self {
    case .keyNotFound(let message), .typeMismatch(let message), .valueNotFound(let message), .dataCorrupted(let message): return message
    }
  }
  public static func dataCorruptedError<Key: EmbeddedCodingKey>(forKey key: Key, in container: EmbeddedKeyedDecodingContainer<Key>, debugDescription: String) -> EmbeddedDecodingError {
    .dataCorrupted(debugDescription)
  }
  public static func dataCorruptedError(in container: EmbeddedSingleValueDecodingContainer, debugDescription: String) -> EmbeddedDecodingError {
    .dataCorrupted(debugDescription)
  }
}

/// Embedded replacement for `try Task.checkCancellation()`, which the
/// Embedded concurrency library marks unavailable. The lowerer rewrites the
/// call; `Task.isCancelled` is available.
public func _embeddedCheckCancellation() throws {
  if Task.isCancelled { throw CancellationError() }
}
#endif
