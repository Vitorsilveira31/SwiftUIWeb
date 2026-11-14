package extension Dictionary where Key == String, Value == JSONValue {
  func text(_ key: String, fallback: String = "") -> String {
    self[key]?.stringValue ?? fallback
  }

  func integer(_ key: String, fallback: Int = 0) -> Int {
    self[key]?.intValue ?? fallback
  }

  func values(_ key: String) -> [[String: JSONValue]] {
    guard case .array(let values) = self[key] else { return [] }
    return values.compactMap {
      if case .object(let object) = $0 { return object }
      return nil
    }
  }
}
