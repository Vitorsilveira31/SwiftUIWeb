/// One value in a keychain query or attribute dictionary. Embedded Swift has no `Any`, so where
/// Security.framework takes `[String: Any]` this module takes `[String: SecValue]`: string, Boolean
/// and integer literals convert on their own, and variables are wrapped, as in
/// `kSecAttrAccount as String: .string(account)` or `kSecValueData as String: .data(token)`.
public enum SecValue: Sendable, Hashable, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
  ExpressibleByIntegerLiteral {
  case string(String)
  case data([UInt8])
  case bool(Bool)
  case int(Int)

  public init(stringLiteral value: String) { self = .string(value) }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(integerLiteral value: Int) { self = .int(value) }

  /// Any byte collection, such as `Data` or `[UInt8]`.
  public static func bytes<Bytes: Sequence>(_ bytes: Bytes) -> SecValue where Bytes.Element == UInt8 {
    .data(Array(bytes))
  }

  public var stringValue: String? { if case .string(let value) = self { return value }; return nil }
  public var dataValue: [UInt8]? { if case .data(let value) = self { return value }; return nil }
  public var boolValue: Bool? {
    switch self {
    case .bool(let value): return value
    case .int(let value): return value != 0
    default: return nil
    }
  }
}

/// Security.framework names its dictionaries and keys with CoreFoundation types. Here they are plain
/// Swift types, so `[kSecClass as String: kSecClassGenericPassword, …] as CFDictionary` still
/// compiles and means the same.
public typealias CFString = String
public typealias CFDictionary = [String: SecValue]
public typealias CFTypeRef = SecItemResult
