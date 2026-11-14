import SwiftParser
import SwiftSyntax

/// `type(of: x) == T.self` reads the dynamic type of an existential, which Embedded Swift has no runtime for; the
/// cast expresses the same test: `(x is T)`, and `!(x is T)` for `!=`. Both sides must be plain dotted names.
///
/// Origin (the previous, text-based lowerer): the `type-of-test` pattern of `transform_detailed`.
public struct TypeOfTestTransform: SourceTransform {
  public let name = "type-of-test"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("type(of:") else { return text }
    let tree = Parser.parse(source: text)
    let finder = SequenceFinder()
    finder.walk(tree)
    var edits: [TextEdit] = []
    for sequence in finder.sequences {
      let elements = Array(sequence.elements)
      for index in 0..<max(elements.count - 2, 0) {
        guard let call = elements[index].as(FunctionCallExprSyntax.self), call.calledExpression.trimmedDescription == "type",
          call.arguments.count == 1, let argument = call.arguments.first, argument.label?.text == "of",
          call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
          let comparison = elements[index + 1].as(BinaryOperatorExprSyntax.self),
          comparison.operator.text == "==" || comparison.operator.text == "!=",
          let metatype = elements[index + 2].as(MemberAccessExprSyntax.self), metatype.declName.baseName.text == "self",
          let base = metatype.base
        else { continue }
        let value = argument.expression.trimmedDescription
        let type = base.trimmedDescription
        guard isDottedIdentifierPath(value), isDottedIdentifierPath(type) else { continue }
        let test = "\(value) is \(type)"
        edits.append(TextEdit(
          start: call.startOffset, end: metatype.endOffset,
          replacement: comparison.operator.text == "==" ? "(\(test))" : "!(\(test))"
        ))
      }
    }
    guard !edits.isEmpty else { return text }
    counts.add("type-of-test", edits.count)
    return try apply(edits, to: text)
  }
}
