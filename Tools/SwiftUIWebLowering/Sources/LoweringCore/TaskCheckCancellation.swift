import SwiftParser
import SwiftSyntax

/// The Embedded concurrency library marks `Task.checkCancellation()` unavailable; `_embeddedCheckCancellation()` has
/// the same semantics. Applied to application sources only, never to the framework's own.
///
/// Origin (the previous, text-based lowerer): the `task-check-cancellation` pattern of `transform_detailed`.
public struct TaskCheckCancellationTransform: SourceTransform {
  public let name = "task-check-cancellation"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("checkCancellation") else { return text }
    let tree = Parser.parse(source: text)
    let finder = CancellationFinder()
    finder.walk(tree)
    guard !finder.calls.isEmpty else { return text }
    counts.add("task-check-cancellation", finder.calls.count)
    return try apply(
      finder.calls.map { TextEdit(start: $0.startOffset, end: $0.endOffset, replacement: "_embeddedCheckCancellation()") },
      to: text
    )
  }
}

/// `Task.checkCancellation()` written as those tokens: a qualified `Swift.Task.checkCancellation()` or a call on a
/// generic `Task<…>` is another expression.
private final class CancellationFinder: SyntaxVisitor {
  var calls: [FunctionCallExprSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    if node.trimmedDescription == "Task.checkCancellation()", let access = node.calledExpression.as(MemberAccessExprSyntax.self),
      access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Task"
    {
      calls.append(node)
    }
    return .visitChildren
  }
}
