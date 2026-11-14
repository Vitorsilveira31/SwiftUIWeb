import SwiftParser
import SwiftSyntax

/// An error interpolated into a message needs `String(describing:)` on an existential, which Embedded Swift cannot
/// do; the two messages the transfer and export flows build lose the interpolation: `"Import failed: \(error)"`
/// becomes `"Import failed"`. Applies to every source, application or framework.
///
/// Origin (the previous, text-based lowerer): the `transfer-error-interpolation` and `export-error-interpolation` patterns of
/// `transform_detailed`. The previous patterns read the raw text, so they also match inside a comment or a longer string;
/// this pass reads string literal expressions only.
public struct ErrorInterpolationTransform: SourceTransform {
  public let name = "error-interpolation"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  private static let messages: [(prefix: String, replacement: String, rule: String)] = [
    ("Import failed: ", "\"Import failed\"", "transfer-error-interpolation"),
    ("Export failed: ", "\"Export failed\"", "export-error-interpolation"),
  ]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains(" failed: \\(error)") else { return text }
    let tree = Parser.parse(source: text)
    let finder = MessageFinder()
    finder.walk(tree)
    var edits: [TextEdit] = []
    for literal in finder.literals {
      guard let message = Self.messages.first(where: { isMessage(literal, prefix: $0.prefix) }) else { continue }
      edits.append(TextEdit(start: literal.startOffset, end: literal.endOffset, replacement: message.replacement))
      counts.add(message.rule, 1)
    }
    return try apply(edits, to: text)
  }

  /// A single-line string made of `prefix` and the interpolation `\(error)`.
  private func isMessage(_ literal: StringLiteralExprSyntax, prefix: String) -> Bool {
    guard literal.openingQuote.tokenKind == .stringQuote, literal.openingPounds == nil else { return false }
    // The parser ends an interpolated string with an empty text segment.
    let segments = Array(literal.segments).filter { segment in
      segment.as(StringSegmentSyntax.self).map { !$0.content.text.isEmpty } ?? true
    }
    guard segments.count == 2 else { return false }
    guard let first = segments[0].as(StringSegmentSyntax.self), first.content.text == prefix,
      let second = segments[1].as(ExpressionSegmentSyntax.self)
    else { return false }
    return second.description == "\\(error)"
  }
}

private final class MessageFinder: SyntaxVisitor {
  var literals: [StringLiteralExprSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
    literals.append(node)
    return .visitChildren
  }
}
