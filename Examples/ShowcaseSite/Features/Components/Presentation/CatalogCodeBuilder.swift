/// Assembles the code a recipe shows: the component on the first line, then one modifier per line, indented as Swift
/// code is written. This is source text, not copy for the screen, so it is not translated.
struct CatalogCodeBuilder {
  private var lines: [String] = []

  init(_ component: String) { lines.append(component) }

  mutating func modifier(_ call: String) { lines.append("  .\(call)") }

  mutating func modifier(_ call: String, if condition: Bool) {
    if condition { modifier(call) }
  }

  var text: String { lines.joined(separator: "\n") }

  /// A Swift string literal for `value`, with the characters that need an escape escaped.
  static func literal(_ value: String) -> String {
    var escaped = ""
    for character in value {
      if character == "\\" || character == "\"" { escaped.append("\\") }
      escaped.append(character)
    }
    return "\"\(escaped)\""
  }

  /// A string literal that ends in an interpolation: `"Guests: \\(count)"`.
  static func literal(_ value: String, endingWith interpolation: String) -> String {
    let literal = literal(value)
    return "\(literal.dropLast())\\(\(interpolation))\""
  }

  /// A number as code: whole numbers without a decimal point.
  static func number(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value))" : "\(value)"
  }
}
