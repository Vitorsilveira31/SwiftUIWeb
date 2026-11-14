import Foundation

/// A JSON value written as pretty-printed JSON: two-space indentation, `"key": value`, one array element per line,
/// `[]` and `{}` for empty containers, and the keys of an object in byte order. The report and the state file are
/// pretty-printed with keys in sorted order, the layout the build's consumers read, so this is not `JSONSerialization`.
enum JSONValue: Equatable {
  case null
  /// Text that is already JSON and already indented for the place it goes to (a cached part of a report, made by
  /// `pretty(atDepth:)`). It is written as it is, so the document reads as if it had been built.
  case raw(String)
  case bool(Bool)
  case int(Int)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  /// The text of the value; the file writers add the final newline.
  /// The value as `pretty()` writes it when it sits at `depth` inside a document (without the indentation of its first
  /// line, which belongs to what holds it).
  func pretty(atDepth depth: Int) -> String {
    var output = ""
    write(into: &output, depth: depth)
    return output
  }

  func pretty() -> String {
    var output = ""
    write(into: &output, depth: 0)
    return output
  }

  private func write(into output: inout String, depth: Int) {
    switch self {
    case .null: output += "null"
    case .raw(let text): output += text
    case .bool(let value): output += value ? "true" : "false"
    case .int(let value): output += String(value)
    case .string(let value): Self.writeString(value, into: &output)
    case .array(let values):
      if values.isEmpty {
        output += "[]"
        return
      }
      output += "[\n"
      for (index, value) in values.enumerated() {
        output += Self.indent(depth + 1)
        value.write(into: &output, depth: depth + 1)
        output += index == values.count - 1 ? "\n" : ",\n"
      }
      output += Self.indent(depth) + "]"
    case .object(let fields):
      if fields.isEmpty {
        output += "{}"
        return
      }
      output += "{\n"
      let keys = fields.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
      for (index, key) in keys.enumerated() {
        output += Self.indent(depth + 1)
        Self.writeString(key, into: &output)
        output += ": "
        fields[key]!.write(into: &output, depth: depth + 1)
        output += index == keys.count - 1 ? "\n" : ",\n"
      }
      output += Self.indent(depth) + "}"
    }
  }

  private static func indent(_ depth: Int) -> String { String(repeating: "  ", count: depth) }

  /// The string escapes of the pretty form: the quote, the backslash, `\b \f \n \r \t`, and `\u00xx` (lowercase) for the
  /// other control characters. Everything else, non-ASCII included, is written as it is.
  private static func writeString(_ text: String, into output: inout String) {
    output += "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": output += "\\\""
      case "\\": output += "\\\\"
      case "\u{08}": output += "\\b"
      case "\u{0C}": output += "\\f"
      case "\n": output += "\\n"
      case "\r": output += "\\r"
      case "\t": output += "\\t"
      default:
        if scalar.value < 0x20 {
          let digits = String(scalar.value, radix: 16)
          output += "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
        } else {
          output.unicodeScalars.append(scalar)
        }
      }
    }
    output += "\""
  }
}

extension JSONValue {
  /// The rule counts as an object.
  init(counts: RuleCounts) {
    self = .object(counts.mapValues { .int($0) })
  }
}
