package extension JSONValue {
  var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  var intValue: Int? {
    // nil for a number Int cannot hold (past 2^31 in the browser build), rather than a trap.
    if case .number(let value) = self { return Int(exactly: value.rounded(.towardZero)) }
    return nil
  }
}
