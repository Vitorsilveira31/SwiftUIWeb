import SwiftSyntax

/// Helpers shared by the passes that rewrite key paths (table sorting, the simple rules). Embedded Swift rejects
/// nested key paths, so a key path in a call becomes a closure or a member name; these helpers read the shapes the
/// previous lowerer's patterns recognized from the tree instead of from text.

/// `[A-Za-z_][A-Za-z0-9_]*`, the identifier every key-path pattern of the previous lowerer spells out.
func isPlainIdentifier(_ text: String) -> Bool {
  guard let first = text.unicodeScalars.first, first == "_" || (first.isASCII && first.properties.isAlphabetic) else { return false }
  return text.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) }
}

/// A key path of plain property components: `\.name`, `\.a.b`, `\Order.status`. A root, when written, is a single
/// identifier; optional chaining, subscripts and generic components are not plain.
struct PropertyKeyPath {
  /// The root type: the `Order` of `\Order.status`.
  let root: String?
  /// The members in order: `["a", "b"]` for `\.a.b`.
  let members: [String]

  var path: String { members.joined(separator: ".") }

  init?(_ expression: ExprSyntax) {
    guard let keyPath = expression.as(KeyPathExprSyntax.self), !keyPath.components.isEmpty else { return nil }
    if let root = keyPath.root {
      guard let identifier = root.as(IdentifierTypeSyntax.self), identifier.genericArgumentClause == nil, isPlainIdentifier(identifier.name.text) else {
        return nil
      }
      self.root = identifier.name.text
    } else {
      root = nil
    }
    var members: [String] = []
    for component in keyPath.components {
      guard component.period != nil,
        let property = component.component.as(KeyPathPropertyComponentSyntax.self),
        property.genericArgumentClause == nil,
        property.declName.argumentNames == nil,
        isPlainIdentifier(property.declName.baseName.text)
      else { return nil }
      members.append(property.declName.baseName.text)
    }
    self.members = members
  }

  /// A key path that starts at the implicit root: `\.a.b`.
  static func rootless(_ expression: ExprSyntax) -> PropertyKeyPath? {
    guard let keyPath = PropertyKeyPath(expression), keyPath.root == nil else { return nil }
    return keyPath
  }
}

/// The name a call is made through: `ForEach` for `ForEach(…)`, `SwiftUI.ForEach(…)` and `ForEach<…>(…)`.
func calleeName(_ expression: ExprSyntax) -> String? {
  if let reference = expression.as(DeclReferenceExprSyntax.self) { return reference.baseName.text }
  if let member = expression.as(MemberAccessExprSyntax.self) { return member.declName.baseName.text }
  if let specialization = expression.as(GenericSpecializationExprSyntax.self) { return calleeName(specialization.expression) }
  return nil
}

/// The name of a call made on a member: `map` for `rows.map(…)` and `.map(…)`.
func memberCallName(_ call: FunctionCallExprSyntax) -> String? {
  guard let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.declName.argumentNames == nil else { return nil }
  return member.declName.baseName.text
}

extension FunctionCallExprSyntax {
  /// Whether the call has any closure after its parentheses.
  var hasTrailingClosure: Bool { trailingClosure != nil || !additionalTrailingClosures.isEmpty }

  /// The parentheses of the argument list when both are written: the parser recovers an unclosed call, with a missing
  /// `)`, but the text it stands for is not a call the lowerer can rewrite safely.
  var parentheses: (left: TokenSyntax, right: TokenSyntax)? {
    guard let left = leftParen, let right = rightParen, left.presence == .present, right.presence == .present else { return nil }
    return (left, right)
  }
}

/// Walks the code of a file for the rules that read calls, member accesses, attributes and declarations. The text of
/// a string literal is not code, so nothing in it is rewritten, but its interpolations are: `"\(rows.map(\.name))"` is
/// a key path in a call like any other. (The previous lowerer reads application sources with their strings unmasked, so
/// it also rewrites what merely looks like code in the text of a literal; the tree does not.)
final class CodeWalker: SyntaxVisitor {
  var onCall: ((FunctionCallExprSyntax) -> Void)?
  var onMember: ((MemberAccessExprSyntax) -> SyntaxVisitorContinueKind)?
  var onAttribute: ((AttributeSyntax) -> Void)?
  var onVariable: ((VariableDeclSyntax) -> Void)?
  var onImport: ((ImportDeclSyntax) -> Void)?

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    onCall?(node)
    return .visitChildren
  }

  override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
    onMember?(node) ?? .visitChildren
  }

  override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
    onAttribute?(node)
    return .visitChildren
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    onVariable?(node)
    return .visitChildren
  }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    onImport?(node)
    return .skipChildren
  }
}

extension SourceFileSyntax {
  func walkCode(
    calls: ((FunctionCallExprSyntax) -> Void)? = nil,
    members: ((MemberAccessExprSyntax) -> SyntaxVisitorContinueKind)? = nil,
    attributes: ((AttributeSyntax) -> Void)? = nil,
    variables: ((VariableDeclSyntax) -> Void)? = nil,
    imports: ((ImportDeclSyntax) -> Void)? = nil
  ) {
    let walker = CodeWalker()
    walker.onCall = calls
    walker.onMember = members
    walker.onAttribute = attributes
    walker.onVariable = variables
    walker.onImport = imports
    walker.walk(self)
  }
}
