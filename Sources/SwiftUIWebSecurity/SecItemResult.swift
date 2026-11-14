/// What `SecItemCopyMatching` (and `SecItemAdd`, when asked) hands back through its result pointer.
/// Security.framework returns `Data`, a dictionary, or an array of dictionaries as `CFTypeRef`; the
/// cases here are those three shapes, and the accessors replace `as? Data` and `as? [String: Any]`.
public enum SecItemResult: Sendable, Equatable {
  /// `kSecReturnData` alone, one item.
  case data([UInt8])
  /// `kSecReturnAttributes` for one item; with `kSecReturnData` too, the bytes are under
  /// `kSecValueData`.
  case attributes([String: SecValue])
  /// `kSecMatchLimitAll`: one dictionary per item.
  case items([[String: SecValue]])

  public var data: [UInt8]? {
    switch self {
    case .data(let bytes): return bytes
    case .attributes(let attributes): return attributes[kSecValueData]?.dataValue
    case .items: return nil
    }
  }

  public var attributes: [String: SecValue]? {
    if case .attributes(let attributes) = self { return attributes }
    return nil
  }

  public var items: [[String: SecValue]] {
    switch self {
    case .items(let items): return items
    case .attributes(let attributes): return [attributes]
    case .data: return []
    }
  }
}
