import SwiftParser
import SwiftSyntax

/// The development profile compiles the lowered tree as full Swift for regular WebAssembly instead of as Embedded Swift
/// (`--full-swift`; Documentation/Performance/BUILD_TIME.md, "The development profile"). In the framework and in an
/// application, `hasFeature(Embedded)` selects the code of the browser product (the exports, BrowserIO, the serialization
/// that needs no reflection), and that is the code the development profile runs too: the two profiles differ in the
/// compiler mode, not in the source they compile. `hasFeature(Embedded)` in an `#if` or `#elseif` condition becomes `true`.
public struct EmbeddedConditionTransform: SourceTransform {
  public let name = "embedded-feature-condition"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.fullSwift }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("hasFeature") else { return text }
    let tree = Parser.parse(source: text)
    let finder = EmbeddedConditionFinder()
    finder.walk(tree)
    guard !finder.edits.isEmpty else { return text }
    counts.add(name, finder.conditions)
    return try apply(finder.edits, to: text)
  }
}

private final class EmbeddedConditionFinder: SyntaxVisitor {
  var edits: [TextEdit] = []
  var conditions = 0

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
    guard let condition = node.condition else { return .visitChildren }
    let finder = EmbeddedFeatureCallFinder()
    finder.walk(condition)
    if !finder.calls.isEmpty {
      conditions += 1
      edits.append(contentsOf: finder.calls.map { TextEdit(start: $0.startOffset, end: $0.endOffset, replacement: "true") })
    }
    return .visitChildren
  }
}

private final class EmbeddedFeatureCallFinder: SyntaxVisitor {
  var calls: [FunctionCallExprSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard node.calledExpression.trimmedDescription == "hasFeature", node.arguments.count == 1,
      let argument = node.arguments.first, argument.label == nil, argument.expression.trimmedDescription == "Embedded"
    else { return .visitChildren }
    calls.append(node)
    return .skipChildren
  }
}
