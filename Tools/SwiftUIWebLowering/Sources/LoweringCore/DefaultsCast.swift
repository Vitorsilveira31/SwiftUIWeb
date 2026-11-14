import SwiftParser
import SwiftSyntax

/// `defaults.object(forKey: "k") as? Bool` is a cast out of `Any`, which Embedded Swift does not have; it becomes a
/// typed read, `defaults._object(forKey: "k", as: Bool.self)`. The cast is rewritten for `Bool`, `String`, `Int`,
/// `Double` and `[String]`, on `object(forKey:)` and `array(forKey:)`.
///
/// Origin (the previous, text-based lowerer): the `defaults-object-cast` pattern of `transform_detailed`.
public struct DefaultsCastTransform: SourceTransform {
  public let name = "defaults-object-cast"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  private static let castTypes: Set<String> = ["Bool", "String", "Int", "Double", "[String]"]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("forKey") else { return text }
    let tree = Parser.parse(source: text)
    let finder = SequenceFinder()
    finder.walk(tree)
    var edits: [TextEdit] = []
    for sequence in finder.sequences {
      let elements = Array(sequence.elements)
      for index in 1..<max(elements.count - 1, 1) {
        guard let cast = elements[index].as(UnresolvedAsExprSyntax.self), cast.questionOrExclamationMark?.tokenKind == .postfixQuestionMark,
          let type = elements[index + 1].as(TypeExprSyntax.self), Self.castTypes.contains(type.trimmedDescription),
          let read = elements[index - 1].as(FunctionCallExprSyntax.self), let access = read.calledExpression.as(MemberAccessExprSyntax.self),
          ["object", "array"].contains(access.declName.baseName.text), access.declName.argumentNames == nil,
          read.arguments.count == 1, read.trailingClosure == nil, read.additionalTrailingClosures.isEmpty,
          let argument = read.arguments.first, argument.label?.text == "forKey"
        else { continue }
        edits.append(TextEdit(
          start: access.period.startOffset, end: type.endOffset,
          replacement: "._object(forKey: \(argument.expression.trimmedDescription), as: \(type.trimmedDescription).self)"
        ))
      }
    }
    guard !edits.isEmpty else { return text }
    counts.add("defaults-object-cast", edits.count)
    return try apply(edits, to: text)
  }
}

/// Every sequence expression: the unfolded form of an expression with binary operators and casts.
final class SequenceFinder: SyntaxVisitor {
  var sequences: [SequenceExprSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
    sequences.append(node)
    return .visitChildren
  }
}
