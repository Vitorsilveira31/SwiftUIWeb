/// Number formatting and text folding by the browser (`Intl`, `String.normalize`). Nil when no host answers (a native
/// build, a test) or the request is malformed. Framework-internal: `SwiftUIWebCore` builds Foundation's formatting on it.
package enum BrowserText {
  /// `decimalText` (as Swift prints the value: `28300.4`, `1e+21`, `nan`) in the style of `options` (`name=value;...`).
  package static func formatNumber(_ decimalText: String, options: String) -> String? {
    var writer = IOWriter()
    writer.u32(0); writer.text(decimalText); writer.text(options)
    return answer(writer)
  }

  /// Foundation's `folding(options:)`: the combining accents (`diacritics`) and/or the case of `value` dropped.
  package static func fold(_ value: String, diacritics: Bool, case foldsCase: Bool) -> String? {
    var writer = IOWriter()
    writer.u32(1); writer.u32((diacritics ? 1 : 0) | (foldsCase ? 2 : 0)); writer.text(value)
    return answer(writer)
  }

  private static func answer(_ request: IOWriter) -> String? {
    guard var reader = try? IORuntime.sync(_BrowserIOProtocol.text, request) else { return nil }
    let present = reader.u32()
    let text = present == 0 ? nil : reader.text()
    return reader.finish() == nil ? text : nil
  }
}
