import SwiftParser
import SwiftSyntax

/// A browser is a desktop host. Application code that branches on the platform has an `os(macOS)` side for exactly
/// that (resizable columns, pointer-driven chrome); WASI matches no platform, so without this rule such a branch
/// compiles to nothing. `os(macOS)` in an `#if` or `#elseif` condition becomes `true`. Applied to application sources
/// only.
///
/// Origin (the previous, text-based lowerer): the `os-macos-condition` rule of `transform_detailed`. The previous rule counts lines and reads the
/// first line of a condition; this one counts conditions and reads all of it.
public struct PlatformConditionTransform: SourceTransform {
  public let name = "os-macos-condition"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("os(macOS)") else { return text }
    let tree = Parser.parse(source: text)
    let finder = ConditionFinder()
    finder.walk(tree)
    guard !finder.edits.isEmpty else { return text }
    counts.add("os-macos-condition", finder.conditions)
    return try apply(finder.edits, to: text)
  }
}

private final class ConditionFinder: SyntaxVisitor {
  var edits: [TextEdit] = []
  var conditions = 0

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
    guard let condition = node.condition else { return .visitChildren }
    let finder = PlatformCallFinder()
    finder.walk(condition)
    if !finder.calls.isEmpty {
      conditions += 1
      edits.append(contentsOf: finder.calls.map { TextEdit(start: $0.startOffset, end: $0.endOffset, replacement: "true") })
    }
    return .visitChildren
  }
}

private final class PlatformCallFinder: SyntaxVisitor {
  var calls: [FunctionCallExprSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    if node.trimmedDescription == "os(macOS)", node.calledExpression.trimmedDescription == "os" { calls.append(node) }
    return .visitChildren
  }
}
