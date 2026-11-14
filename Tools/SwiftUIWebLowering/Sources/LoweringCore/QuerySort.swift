import SwiftParser
import SwiftSyntax

/// `@Query(sort: \Model.member)`: a key path in the sort becomes a closure reading the member,
/// `@Query(sort: { (model: Model) in model.member })`. The key path must be a plain property path rooted in a
/// simple type name and the first argument of the attribute.
///
/// Origin (the previous, text-based lowerer): the `query-sort-key-path` pattern of `transform_detailed`.
public struct QuerySortTransform: SourceTransform {
  public let name = "query-sort-key-path"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("@Query") else { return text }
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    let finder = QueryFinder()
    finder.walk(tree)
    var edits: [TextEdit] = []
    for attribute in finder.queries {
      guard let leftParen = attribute.leftParen, case .argumentList(let arguments)? = attribute.arguments,
        let first = arguments.first, let label = first.label, label.text == "sort",
        let colon = first.colon, colon.leadingTrivia.isEmpty,
        let keyPath = first.expression.as(KeyPathExprSyntax.self), let path = Self.propertyPath(keyPath),
        // The previous pattern normalizes the whitespace between `(`, `sort:` and the key path, so only whitespace is.
        bytes.isBlank(leftParen.endOffset, label.startOffset), bytes.isBlank(colon.endOffset, keyPath.startOffset)
      else { continue }
      edits.append(TextEdit(
        start: leftParen.endOffset, end: keyPath.endOffset,
        replacement: "sort: { (model: \(path.root)) in model.\(path.members) }"
      ))
    }
    guard !edits.isEmpty else { return text }
    counts.add("query-sort-key-path", edits.count)
    return try apply(edits, to: text)
  }

  /// `\Root.a.b` as its root type name and its dotted members; nil for a key path with a subscript, an optional
  /// chain or a qualified root.
  private static func propertyPath(_ keyPath: KeyPathExprSyntax) -> (root: String, members: String)? {
    guard let root = keyPath.root?.as(IdentifierTypeSyntax.self), root.genericArgumentClause == nil,
      !keyPath.components.isEmpty
    else { return nil }
    var members: [String] = []
    for component in keyPath.components {
      guard case .property(let property) = component.component, property.genericArgumentClause == nil,
        isDottedIdentifierPath(property.declName.baseName.text), !property.declName.baseName.text.contains(".")
      else { return nil }
      members.append(property.declName.baseName.text)
    }
    return (root.name.text, members.joined(separator: "."))
  }
}

private final class QueryFinder: SyntaxVisitor {
  var queries: [AttributeSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
    if node.attributeName.trimmedDescription == "Query" { queries.append(node) }
    return .visitChildren
  }
}
