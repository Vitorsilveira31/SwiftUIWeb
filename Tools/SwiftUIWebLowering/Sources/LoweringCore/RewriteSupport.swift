import SwiftSyntax

// Helpers the single-node text rewrites share.

extension SourceBytes {
  /// Whether the bytes in `start..<end` are all spaces, tabs or line breaks.
  func isBlank(_ start: Int, _ end: Int) -> Bool {
    guard start <= end, end <= bytes.count else { return false }
    return bytes[start..<end].allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
  }

  /// The indentation of the line `offset` starts, when nothing but spaces and tabs precede `offset` on that line; nil
  /// when code or a comment does. The previous lowerer's `^[ \t]*` anchor.
  func indentation(before offset: Int) -> String? {
    let start = lineStart(offset)
    guard bytes[start..<offset].allSatisfy({ $0 == 0x20 || $0 == 0x09 }) else { return nil }
    return slice(start, offset)
  }
}

/// Whether `text` is a plain dotted identifier path, `Outer.Inner.name`, as the previous lowerer's
/// `[A-Za-z_][A-Za-z0-9_\.]*` reads one.
func isDottedIdentifierPath(_ text: String) -> Bool {
  guard text.first.map({ $0 == "_" || ($0.isASCII && $0.isLetter) }) == true else { return false }
  return text.unicodeScalars.allSatisfy { scalar in
    scalar == "_" || scalar == "." || (scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)))
  }
}
