import Foundation

/// A source the lowerer refuses to rewrite: the run stops with `path:line:column: [code] message`, as the previous lowerer's
/// `LoweringError` does.
public struct LoweringError: Error, CustomStringConvertible, Sendable {
  /// `SWUI-L001` (an `@Observable` declaration that is not a class the lowerer can rewrite) or `SWUI-L002` (an
  /// initializer assignment whose value cannot be delimited) or `SWUI-L003` (a rule whose edits overlap or fall outside
  /// the text it was given).
  public let code: String
  public let message: String
  /// UTF-8 offset into the source the transform was given.
  public let offset: Int

  public init(code: String, message: String, offset: Int) {
    self.code = code
    self.message = message
    self.offset = offset
  }

  public var description: String { "[\(code)] \(message)" }

  /// The 1-based line and column of `offset` in `text`; the column counts Unicode scalars, as the previous lowerer's
  /// `SourcePosition` (`chars().count()`) does.
  public static func position(of offset: Int, in text: String) -> (line: Int, column: Int) {
    let bytes = Array(text.utf8)
    let end = min(max(offset, 0), bytes.count)
    var line = 1
    var lineStart = 0
    for index in 0..<end where bytes[index] == 0x0A {
      line += 1
      lineStart = index + 1
    }
    let column = String(decoding: bytes[lineStart..<end], as: UTF8.self).unicodeScalars.count + 1
    return (line, column)
  }

  /// `path:line:column: [code] message`, the form every lowering failure is printed in.
  public func formatted(path: String, source: String) -> String {
    let place = Self.position(of: offset, in: source)
    return "\(path):\(place.line):\(place.column): \(self)"
  }
}
