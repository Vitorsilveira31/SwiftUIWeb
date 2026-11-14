import Foundation
import SwiftParser
import SwiftSyntax

/// Embedded Swift cannot call a protocol-extension method through an existential ("cannot specialize generic function or
/// default protocol method"), but it can call a protocol requirement. For a protocol declared in the same file, the
/// plain (non-generic, unconstrained) methods and computed properties that its extensions add are also declared as
/// requirements, the extension staying as their default implementation:
///
/// ```swift
/// protocol G { func name() -> String }
/// extension G { public func greet() -> String { name() } }   // `func greet() -> String` is added to `G`
/// ```
///
/// Only members that are public (declared `public`, or in a `public`/`package` extension and not marked `private`,
/// `fileprivate` or `internal`) are promoted: the requirement of a public protocol is public, and a conforming type's own
/// internal method of the same name would stop satisfying it. Static members, `hash`, `==`, generic methods and methods
/// without a body are left alone, as is a name the protocol already declares. The requirement is the member's signature
/// as written (from the start of its line to the body's brace, so attributes on their own line and the access modifiers
/// and `nonisolated` are not part of it); a computed property becomes `var name: Type { get }`. Applied to application
/// sources only.
///
/// Origin (the previous, text-based lowerer): `promote_protocol_extension_members`. Rule: `protocol-extension-requirement`.
///
/// What the tree decides differently from the line scan: a one-line computed property (`var x: Int { 0 }`) is promoted
/// like a multi-line one (the scan wants the brace to end the line, so a trailing comment hid it too); a method with a
/// `<` anywhere in its first line (`-> Array<Int>`, `a < b`) is not taken for a generic one, and a braces-in-a-string
/// body no longer shifts the member depth; a name the protocol declares is matched as a whole name (`func image` no
/// longer finds `func imageURL`); a protocol or extension with attributes on its line, or its brace on the next one,
/// is read; and a member spelled with `some` is left out (its requirement would not compile).
public struct ProtocolExtensionTransform: SourceTransform {
  public let name = "protocol-extension-requirement"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  /// Modifiers the previous member pattern accepts before `func` / `var`. A member with another one (`static`, `class`,
  /// `override`, `private`, `fileprivate`, `open`) is not read.
  private static let acceptedModifiers: Set<Keyword> = [.public, .internal, .package, .nonisolated, .mutating, .final]

  /// Modifiers of the extension line that the previous pattern accepts.
  private static let acceptedExtensionModifiers: Set<Keyword> = [.public, .internal, .package]

  /// Modifiers dropped from a requirement's signature: a requirement has the protocol's access.
  private static let droppedModifiers: Set<Keyword> = [.public, .internal, .package, .nonisolated]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("protocol"), text.contains("extension") else { return text }
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    let declarations = DeclarationCollector()
    declarations.walk(tree)

    var edits: [TextEdit] = []
    var promoted = 0
    var done = Set<String>()
    for declaration in declarations.protocols {
      let name = declaration.name.text
      // The first protocol of a name, as the previous lowerer's header search finds it.
      guard done.insert(name).inserted, declaration.memberBlock.rightBrace.presence == .present else { continue }
      var requirements: [Requirement] = []
      for candidate in declarations.extensions where extends(candidate, protocolNamed: name) {
        requirements.append(contentsOf: self.requirements(in: candidate, bytes: bytes))
      }
      guard !requirements.isEmpty else { continue }

      var declared = declaredKeys(of: declaration)
      var additions = ""
      for requirement in requirements where declared.insert(requirement.key).inserted {
        additions += "  \(requirement.text)\n"
        promoted += 1
      }
      if !additions.isEmpty {
        edits.append(.insert(additions, at: declaration.memberBlock.rightBrace.startOffset))
      }
    }
    guard !edits.isEmpty else { return text }
    counts.add("protocol-extension-requirement", promoted)
    return try apply(edits, to: text)
  }

  // MARK: Declarations

  /// `extension Name { … }`: no conformance, no `where`, no generic arguments, a closed body, and at most one of
  /// `public`, `internal`, `package` before it.
  private func extends(_ declaration: ExtensionDeclSyntax, protocolNamed name: String) -> Bool {
    guard let type = declaration.extendedType.as(IdentifierTypeSyntax.self), type.name.text == name, type.genericArgumentClause == nil,
      declaration.inheritanceClause == nil, declaration.genericWhereClause == nil,
      declaration.memberBlock.rightBrace.presence == .present,
      declaration.modifiers.count <= 1,
      declaration.modifiers.allSatisfy({ isPlain($0, in: Self.acceptedExtensionModifiers) })
    else { return false }
    return true
  }

  private func isPlain(_ modifier: DeclModifierSyntax, in accepted: Set<Keyword>) -> Bool {
    if case .keyword(let keyword) = modifier.name.tokenKind { return modifier.detail == nil && accepted.contains(keyword) }
    return false
  }

  /// The members the protocol declares itself, by kind and name.
  private func declaredKeys(of declaration: ProtocolDeclSyntax) -> Set<String> {
    var keys = Set<String>()
    for member in flattenedMembers(declaration.memberBlock.members) {
      if let function = member.as(FunctionDeclSyntax.self) {
        keys.insert("func \(function.name.text)")
      } else if let variable = member.as(VariableDeclSyntax.self) {
        for binding in variable.bindings {
          if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) { keys.insert("var \(pattern.identifier.text)") }
        }
      }
    }
    return keys
  }

  // MARK: Requirements

  private struct Requirement {
    /// `func name` / `var name`: what the protocol is checked for.
    let key: String
    let text: String
  }

  /// The requirements an extension's members ask for, in source order.
  private func requirements(in declaration: ExtensionDeclSyntax, bytes: SourceBytes) -> [Requirement] {
    let extensionIsPublic = declaration.modifiers.contains(.public) || declaration.modifiers.contains(.package)
    var result: [Requirement] = []
    for member in flattenedMembers(declaration.memberBlock.members) {
      if let function = member.as(FunctionDeclSyntax.self) {
        guard isPromotable(function.modifiers, extensionIsPublic: extensionIsPublic), function.genericParameterClause == nil,
          !function.name.text.hasPrefix("=="), function.name.text != "hash", !isOpaque(function.signature),
          let body = function.body, body.leftBrace.presence == .present
        else { continue }
        result.append(
          Requirement(
            key: "func \(function.name.text)",
            text: signature(of: function, from: declaration.memberBlock.leftBrace.endOffset, upTo: body.leftBrace, bytes: bytes)))
      } else if let variable = member.as(VariableDeclSyntax.self) {
        guard isPromotable(variable.modifiers, extensionIsPublic: extensionIsPublic),
          variable.bindingSpecifier.tokenKind == .keyword(.var), variable.bindings.count == 1,
          let binding = variable.bindings.first, let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
          let type = binding.typeAnnotation?.type, !isOpaque(type), binding.accessorBlock != nil
        else { continue }
        let name = pattern.identifier.text
        result.append(Requirement(key: "var \(name)", text: "var \(name): \(type.trimmedDescription) { get }"))
      }
    }
    return result
  }

  /// Whether a type is spelled with `some`: a requirement cannot be opaque (`var body: some View`), and an opaque
  /// parameter makes a method generic.
  private func isOpaque(_ node: some SyntaxProtocol) -> Bool {
    node.tokens(viewMode: .sourceAccurate).contains { $0.tokenKind == .keyword(.some) }
  }

  /// A public instance member: modifiers the previous pattern reads, and `public` of its own or of a public extension.
  private func isPromotable(_ modifiers: DeclModifierListSyntax, extensionIsPublic: Bool) -> Bool {
    guard modifiers.allSatisfy({ isPlain($0, in: Self.acceptedModifiers) }) else { return false }
    if modifiers.contains(.public) { return true }
    return extensionIsPublic && !modifiers.contains(.internal)
  }

  /// The declaration from the start of the line `func` is on (or the extension's brace, when they share a line) to the
  /// body's brace, without the modifiers a requirement does not carry, trimmed.
  private func signature(of function: FunctionDeclSyntax, from floor: Int, upTo brace: TokenSyntax, bytes: SourceBytes) -> String {
    let start = max(bytes.lineStart(function.funcKeyword.startOffset), floor)
    var signature = ""
    var cursor = start
    for modifier in function.modifiers where modifier.startOffset >= start && isPlain(modifier, in: Self.droppedModifiers) {
      signature += bytes.slice(cursor, modifier.startOffset)
      cursor = modifier.endPosition.utf8Offset
    }
    signature += bytes.slice(cursor, brace.startOffset)
    return signature.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Every protocol and extension of a file, in source order, wherever it is declared.
private final class DeclarationCollector: SyntaxVisitor {
  private(set) var protocols: [ProtocolDeclSyntax] = []
  private(set) var extensions: [ExtensionDeclSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    protocols.append(node)
    return .visitChildren
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    extensions.append(node)
    return .visitChildren
  }
}
