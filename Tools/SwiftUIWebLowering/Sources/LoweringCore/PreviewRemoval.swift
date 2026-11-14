import SwiftParser
import SwiftSyntax

/// `#Preview { … }` and `struct …: PreviewProvider { … }` are compile-time conveniences for Xcode's canvas and produce
/// nothing a running app uses; each is removed with its body, together with its indentation and the line break after
/// it. A declaration that does not start its line, or whose body is not closed, is left for the compiler to report.
///
/// Origin (the previous, text-based lowerer): `remove_preview_macros`. The pass runs ahead of `view-inputs`, as the previous pipeline does: a view
/// nested in a preview provider must be gone before it is given a comparison that would outlive it.
public struct PreviewRemovalTransform: SourceTransform {
  public let name = "preview-macro"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("#Preview") || text.contains("PreviewProvider") else { return text }
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    let finder = PreviewFinder()
    finder.walk(tree)
    var edits: [TextEdit] = []
    for node in finder.previews {
      let start = node.startOffset
      guard bytes.indentation(before: start) != nil else { continue }
      var end = node.endOffset
      if end < bytes.bytes.count, bytes.bytes[end] == 0x0A { end += 1 }
      edits.append(.remove(bytes.lineStart(start), end))
    }
    guard !edits.isEmpty else { return text }
    counts.add("preview-macro", edits.count)
    return try apply(edits, to: text)
  }
}

/// The outermost preview declarations: what a removed preview contains goes with it.
private final class PreviewFinder: SyntaxVisitor {
  var previews: [Syntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
    guard node.macroName.text == "Preview", node.trailingClosure?.rightBrace.presence == .present else { return .visitChildren }
    previews.append(Syntax(node))
    return .skipChildren
  }

  override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
    guard node.macroName.text == "Preview", node.trailingClosure?.rightBrace.presence == .present else { return .visitChildren }
    previews.append(Syntax(node))
    return .skipChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    guard node.memberBlock.rightBrace.presence == .present,
      node.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription == "PreviewProvider"
    else { return .visitChildren }
    previews.append(Syntax(node))
    return .skipChildren
  }
}
