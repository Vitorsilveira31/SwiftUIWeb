import SwiftSyntax

/// A replacement of the UTF-8 byte range `start..<end` of a source text.
struct TextEdit {
  var start: Int
  var end: Int
  var replacement: String

  static func insert(_ text: String, at offset: Int) -> TextEdit {
    TextEdit(start: offset, end: offset, replacement: text)
  }

  static func remove(_ start: Int, _ end: Int) -> TextEdit {
    TextEdit(start: start, end: end, replacement: "")
  }
}

/// Applies non-overlapping edits. Edits at the same offset keep their order in `edits`. Two edits that overlap, or an
/// edit outside the text, is a `LoweringError` (`SWUI-L003`): a source the rules cannot rewrite safely fails the run
/// with its file and rule named, instead of trapping.
func apply(_ edits: [TextEdit], to text: String) throws -> String {
  guard !edits.isEmpty else { return text }
  let bytes = Array(text.utf8)
  let ordered = edits.enumerated().sorted { lhs, rhs in
    lhs.element.start != rhs.element.start ? lhs.element.start < rhs.element.start : lhs.offset < rhs.offset
  }.map(\.element)
  var output: [UInt8] = []
  output.reserveCapacity(bytes.count + 256)
  var cursor = 0
  for edit in ordered {
    guard edit.start >= cursor && edit.end >= edit.start && edit.end <= bytes.count else {
      throw LoweringError(code: "SWUI-L003", message: "overlapping or out-of-range edit at bytes \(edit.start)..<\(edit.end)", offset: edit.start)
    }
    output.append(contentsOf: bytes[cursor..<edit.start])
    output.append(contentsOf: edit.replacement.utf8)
    cursor = edit.end
  }
  output.append(contentsOf: bytes[cursor...])
  return String(decoding: output, as: UTF8.self)
}

extension SyntaxProtocol {
  /// Offset of the first byte of the node's first token, after its leading trivia.
  var startOffset: Int { positionAfterSkippingLeadingTrivia.utf8Offset }
  /// Offset just after the node's last token, before its trailing trivia.
  var endOffset: Int { endPositionBeforeTrailingTrivia.utf8Offset }
}

/// Byte-level helpers over a source text.
struct SourceBytes {
  let bytes: [UInt8]

  init(_ text: String) { bytes = Array(text.utf8) }

  /// Offset of the first byte of the line that holds `offset`.
  func lineStart(_ offset: Int) -> Int {
    var index = min(offset, bytes.count)
    while index > 0 && bytes[index - 1] != 0x0A { index -= 1 }
    return index
  }

  /// Offset of the newline that ends the line holding `offset`, or the end of the text.
  func lineEnd(_ offset: Int) -> Int {
    var index = min(offset, bytes.count)
    while index < bytes.count && bytes[index] != 0x0A { index += 1 }
    return index
  }

  func slice(_ start: Int, _ end: Int) -> String {
    String(decoding: bytes[start..<end], as: UTF8.self)
  }
}
