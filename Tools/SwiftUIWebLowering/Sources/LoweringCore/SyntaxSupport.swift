import SwiftSyntax

/// One struct, class, enum, actor or extension with its fully qualified path. An extension's path is its own
/// (possibly dotted) name; a nested type's path is its lexical parent's path plus its name.
struct TypeScope {
  let node: Syntax
  let path: [String]
  var end: Int { node.endOffset }
}

/// Collects every type scope of a file in source order together with its qualified path.
final class ScopeCollector: SyntaxVisitor {
  private(set) var scopes: [TypeScope] = []
  private var stack: [[String]] = []

  init() { super.init(viewMode: .sourceAccurate) }

  private func enter(_ node: Syntax, name: String, isExtension: Bool, closed: Bool) {
    let path: [String]
    if isExtension {
      path = name.split(separator: ".").map(String.init)
    } else {
      path = (stack.last ?? []) + [name]
    }
    // A declaration whose body is not closed has no scope: the parser recovers it, but the text it stands for is not
    // a declaration the lowerer can rewrite safely (the previous lowerer finds no matching brace either).
    if closed { scopes.append(TypeScope(node: node, path: path)) }
    stack.append(path)
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(Syntax(node), name: node.name.text, isExtension: false, closed: node.memberBlock.rightBrace.presence == .present)
    return .visitChildren
  }
  override func visitPost(_ node: StructDeclSyntax) { stack.removeLast() }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(Syntax(node), name: node.name.text, isExtension: false, closed: node.memberBlock.rightBrace.presence == .present)
    return .visitChildren
  }
  override func visitPost(_ node: ClassDeclSyntax) { stack.removeLast() }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(Syntax(node), name: node.name.text, isExtension: false, closed: node.memberBlock.rightBrace.presence == .present)
    return .visitChildren
  }
  override func visitPost(_ node: EnumDeclSyntax) { stack.removeLast() }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(Syntax(node), name: node.name.text, isExtension: false, closed: node.memberBlock.rightBrace.presence == .present)
    return .visitChildren
  }
  override func visitPost(_ node: ActorDeclSyntax) { stack.removeLast() }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(Syntax(node), name: extendedTypeName(node.extendedType), isExtension: true, closed: node.memberBlock.rightBrace.presence == .present)
    return .visitChildren
  }
  override func visitPost(_ node: ExtensionDeclSyntax) { stack.removeLast() }
}

/// `Outer.Inner` for an extended type, without generic arguments.
func extendedTypeName(_ type: TypeSyntax) -> String {
  if let member = type.as(MemberTypeSyntax.self) {
    return extendedTypeName(member.baseType) + "." + member.name.text
  }
  if let identifier = type.as(IdentifierTypeSyntax.self) {
    return identifier.name.text
  }
  return type.trimmedDescription
}

extension TypeScope {
  static func collect(_ tree: SourceFileSyntax) -> [TypeScope] {
    let collector = ScopeCollector()
    collector.walk(tree)
    return collector.scopes
  }
}

/// The scope of a declaration node, by identity.
struct ScopeIndex {
  let scopes: [TypeScope]
  private let byID: [SyntaxIdentifier: TypeScope]

  init(_ tree: SourceFileSyntax) {
    scopes = TypeScope.collect(tree)
    byID = Dictionary(uniqueKeysWithValues: scopes.map { ($0.node.id, $0) })
  }

  func scope(of node: some SyntaxProtocol) -> TypeScope? { byID[node.id] }
  func path(of node: some SyntaxProtocol) -> [String]? { byID[node.id]?.path }
}

// MARK: - Members

/// The member declarations of a type body, looking into every branch of a conditional block as the previous lowerer's
/// line scan does: it counts brace depth, not `#if` conditions, so a member in any branch is a member.
func flattenedMembers(_ members: MemberBlockItemListSyntax) -> [DeclSyntax] {
  var result: [DeclSyntax] = []
  for item in members {
    if let conditional = item.decl.as(IfConfigDeclSyntax.self) {
      for clause in conditional.clauses {
        if case .decls(let inner)? = clause.elements {
          result.append(contentsOf: flattenedMembers(inner))
        }
      }
    } else {
      result.append(item.decl)
    }
  }
  return result
}

// MARK: - Modifiers and attributes

extension DeclModifierListSyntax {
  func contains(_ keyword: Keyword) -> Bool {
    contains { $0.name.tokenKind == .keyword(keyword) }
  }

  /// The modifier names in order, with a parenthesized detail kept: `private(set)`.
  var spelled: [String] {
    map { modifier in
      modifier.detail.map { modifier.name.text + $0.trimmedDescription } ?? modifier.name.text
    }
  }
}

extension AttributeListSyntax {
  /// The names of the attributes, as written, without their arguments: `Environment`, `SwiftUI.State`.
  var names: [String] {
    compactMap { element in
      element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
    }
  }
}

// MARK: - Types

/// The last component of a conformance as the previous lowerer reads it: the text after the last `.` or space.
func lastComponent(_ type: TypeSyntax) -> String {
  let text = type.trimmedDescription
  return text.split(whereSeparator: { $0 == "." || $0 == " " }).last.map(String.init) ?? ""
}

func inheritedNames(_ clause: InheritanceClauseSyntax?) -> [String] {
  clause?.inheritedTypes.map { lastComponent($0.type) } ?? []
}

func isWhitespaceOnly(_ trivia: Trivia) -> Bool {
  trivia.allSatisfy { piece in
    switch piece {
    case .spaces, .tabs, .newlines, .carriageReturns, .carriageReturnLineFeeds: true
    default: false
    }
  }
}

extension String {
  var isIdentifierStart: Bool {
    guard let first = unicodeScalars.first else { return false }
    return first == "_" || (first.isASCII && first.properties.isAlphabetic)
  }
}
