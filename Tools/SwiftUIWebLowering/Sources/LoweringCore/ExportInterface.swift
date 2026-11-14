import SwiftParser
import SwiftSyntax

/// Marks the framework's non-generic functions `@export(interface)`, so that the library compiles their bodies once, in
/// its own object code, instead of deserializing and recompiling them inside the application module on every save.
/// The bodies leave the library's `.swiftmodule`, the application only calls the symbol, and an edit to such a body leaves
/// the module byte-identical: the application is relinked, not recompiled. The library targets are built with
/// `DeferredCodeGen` for this (see `Tools/run-browser-embedded.sh`).
///
/// It runs only in the debug development loop, behind `--export-interface`, and only on framework files: an application
/// file is lowered with `lowerCodable`, which is never combined with it. A release build keeps the bodies in the
/// `.swiftmodule` as before.
///
/// Rule: `export-interface`. A declaration is skipped when any of its conditions fails: it is generic or lives in a generic
/// context, it is a dynamically dispatched or overridable member, its signature has an opaque or existential-composition
/// type or is `async`/`rethrows`, it carries an attribute that changes how the compiler emits it, or it is already marked.
/// Where a rule could be read two ways, the stricter reading is taken (more declarations are skipped).
public struct ExportInterfaceTransform: SourceTransform {
  public let name = "export-interface"

  public init() {}

  /// Framework files, and application files too when `--export-interface-application` is given.
  public func applies(to options: LoweringOptions) -> Bool {
    options.exportInterface && (!options.lowerCodable || options.exportInterfaceApplication)
  }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("func") || text.contains("init") else { return text }
    let tree = Parser.parse(source: text)
    // Protocols and generic types declared in this file are known even when the caller's set does not include them.
    let generic = options.genericTypeNames.union(GenericTypeFinder.names(in: tree))
    let finder = ExportCandidateFinder(genericTypeNames: generic)
    finder.walk(tree)
    counts.add(name, finder.edits.count)
    return try apply(finder.edits, to: text)
  }

  /// Attributes that change how a declaration is emitted or who may call it. A declaration that carries one keeps its
  /// body in the interface (or the compiler owns the symbol), so it is skipped.
  static let skippedAttributes: Set<String> = [
    "inlinable", "_transparent", "_alwaysEmitIntoClient", "usableFromInline", "inline", "_effects", "export", "_silgen_name",
    "_cdecl", "c", "_expose", "_used", "_section", "objc", "_spi", "_implements", "_specialize", "backDeployed",
    "_dynamicReplacement", "derivative", "differentiable", "main", "_disfavoredOverload", "preconcurrency",
    "_unsafeInheritExecutor", "_optimize", "_semantics", "_noAllocation", "_noLocks", "_noExistentials", "_noObjCBridging",
  ]

  /// Modifiers that make a member overridable, required or dynamically dispatched.
  static let skippedModifiers: Set<String> = ["dynamic", "optional", "required", "convenience", "override"]

  /// Standard-library names that are generic (or protocols) although the lowerer scans no file that declares them.
  /// Any name starting with `Unsafe` is generic too (`UnsafeMutablePointer` and its kin).
  static let standardGenericNames: Set<String> = [
    "Array", "ArraySlice", "ContiguousArray", "Dictionary", "Set", "Optional", "Result", "Collection", "Sequence",
    "RandomAccessCollection", "BidirectionalCollection", "MutableCollection", "RangeReplaceableCollection", "Equatable",
    "Hashable", "Comparable", "Identifiable", "Error", "Encodable", "Decodable", "Codable", "CustomStringConvertible",
    "StringProtocol", "BinaryInteger", "FixedWidthInteger", "FloatingPoint", "BinaryFloatingPoint", "Numeric",
    "SignedNumeric", "Strideable", "AsyncSequence", "AsyncIteratorProtocol", "IteratorProtocol", "RawRepresentable",
    "CaseIterable", "Sendable", "ExpressibleByStringLiteral", "ExpressibleByIntegerLiteral", "ExpressibleByArrayLiteral",
    "ExpressibleByDictionaryLiteral", "ExpressibleByNilLiteral", "ExpressibleByBooleanLiteral", "ExpressibleByFloatLiteral",
    "ExpressibleByUnicodeScalarLiteral", "ExpressibleByExtendedGraphemeClusterLiteral", "ExpressibleByStringInterpolation",
    "OptionSet", "SetAlgebra", "Range", "ClosedRange", "KeyPath", "WritableKeyPath", "ReferenceWritableKeyPath",
    "PartialKeyPath",
  ]
}

/// The generic types and protocols of a file: every `struct`, `class`, `enum` or `actor` with a generic parameter clause,
/// every `protocol`, and every type nested at any depth inside one of those (and inside an extension, whose extended type
/// may be generic in another file). A nested type is recorded by its simple name and by its dotted path (`Outer.Inner`).
/// The workspace driver unions these over every file of the run (`GenericTypeScan`).
enum GenericTypeFinder {
  static func names(in tree: SourceFileSyntax) -> Set<String> {
    let finder = GenericTypeNameCollector()
    finder.walk(tree)
    return finder.names
  }
}

/// The per-file scan the workspace driver caches. A file that declares no generic type, protocol or extension cannot
/// contribute a name, so the parse is skipped for it.
enum GenericTypeScan {
  static func names(in text: String) -> Set<String> {
    guard text.contains("<") || text.contains("protocol") || text.contains("extension") else { return [] }
    return GenericTypeFinder.names(in: Parser.parse(source: text))
  }
}

private final class GenericTypeNameCollector: SyntaxVisitor {
  private struct Scope {
    let path: [String]
    let marked: Bool
  }

  private(set) var names = Set<String>()
  private var stack: [Scope] = []

  init() { super.init(viewMode: .sourceAccurate) }

  /// Opens a nominal type's scope. It is recorded when it is generic, a protocol, or nested in a recorded scope.
  private func open(_ name: String, generic: Bool) {
    let parent = stack.last
    let marked = generic || (parent?.marked ?? false)
    let path = (parent?.path ?? []) + [name]
    if marked {
      names.insert(name)
      names.insert(path.joined(separator: "."))
    }
    stack.append(Scope(path: path, marked: marked))
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    open(node.name.text, generic: node.genericParameterClause != nil)
    return .visitChildren
  }
  override func visitPost(_ node: StructDeclSyntax) { stack.removeLast() }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    open(node.name.text, generic: node.genericParameterClause != nil)
    return .visitChildren
  }
  override func visitPost(_ node: ClassDeclSyntax) { stack.removeLast() }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    open(node.name.text, generic: node.genericParameterClause != nil)
    return .visitChildren
  }
  override func visitPost(_ node: EnumDeclSyntax) { stack.removeLast() }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    open(node.name.text, generic: node.genericParameterClause != nil)
    return .visitChildren
  }
  override func visitPost(_ node: ActorDeclSyntax) { stack.removeLast() }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    open(node.name.text, generic: true)
    return .visitChildren
  }
  override func visitPost(_ node: ProtocolDeclSyntax) { stack.removeLast() }

  /// An extension is a container whose nested types may belong to a generic type declared elsewhere, so they are recorded.
  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    let path = extendedTypeName(node.extendedType).split(separator: ".").map(String.init)
    stack.append(Scope(path: path, marked: true))
    return .visitChildren
  }
  override func visitPost(_ node: ExtensionDeclSyntax) { stack.removeLast() }
}

/// Finds the declarations the rule marks and records one insertion for each.
private final class ExportCandidateFinder: SyntaxVisitor {
  let genericTypeNames: Set<String>
  private(set) var edits: [TextEdit] = []

  init(genericTypeNames: Set<String>) {
    self.genericTypeNames = genericTypeNames
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    consider(
      node, attributes: node.attributes, modifiers: node.modifiers, signature: node.signature,
      generic: node.genericParameterClause, whereClause: node.genericWhereClause, body: node.body
    )
    return .visitChildren
  }

  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    consider(
      node, attributes: node.attributes, modifiers: node.modifiers, signature: node.signature,
      generic: node.genericParameterClause, whereClause: node.genericWhereClause, body: node.body
    )
    return .visitChildren
  }

  private func consider(
    _ node: some DeclSyntaxProtocol, attributes: AttributeListSyntax, modifiers: DeclModifierListSyntax, signature: FunctionSignatureSyntax,
    generic: GenericParameterClauseSyntax?, whereClause: GenericWhereClauseSyntax?, body: CodeBlockSyntax?
  ) {
    guard generic == nil, whereClause == nil else { return }
    guard let body, body.leftBrace.presence == .present, body.rightBrace.presence == .present else { return }
    guard Self.hasNoSkippedAttribute(attributes),
      !modifiers.contains(where: { ExportInterfaceTransform.skippedModifiers.contains($0.name.text) })
    else { return }
    guard Self.signatureIsExportable(signature) else { return }
    guard isInEligibleContext(node) else { return }
    edits.append(.insert("@export(interface) ", at: node.startOffset))
  }

  static func hasNoSkippedAttribute(_ attributes: AttributeListSyntax) -> Bool {
    let collector = AttributeNameCollector()
    collector.walk(attributes)
    return collector.names.isDisjoint(with: ExportInterfaceTransform.skippedAttributes)
  }

  /// No `some` (opaque result or parameter), no `async` or `rethrows`, and no `any` composed with `&`. The check is on the
  /// signature's tokens, so a parameter named like one of those words also skips the declaration (the conservative reading).
  static func signatureIsExportable(_ signature: FunctionSignatureSyntax) -> Bool {
    let words = Set(signature.tokens(viewMode: .sourceAccurate).map(\.text))
    if words.contains("some") || words.contains("async") || words.contains("rethrows") { return false }
    if words.contains("any") && words.contains("&") { return false }
    return true
  }

  /// Walks up to the file. Every enclosing declaration must be a file-scope type or extension that is not generic, not a
  /// protocol, and (for a class) final; no enclosing function, closure, accessor or body is allowed (a local function).
  private func isInEligibleContext(_ node: some SyntaxProtocol) -> Bool {
    var ancestor = node.parent
    while let current = ancestor {
      if current.is(CodeBlockSyntax.self) || current.is(ClosureExprSyntax.self) || current.is(AccessorDeclSyntax.self)
        || current.is(FunctionDeclSyntax.self) || current.is(InitializerDeclSyntax.self) || current.is(DeinitializerDeclSyntax.self)
        || current.is(ProtocolDeclSyntax.self)
      {
        return false
      }
      if let declaration = current.as(StructDeclSyntax.self) {
        guard declaration.genericParameterClause == nil else { return false }
      } else if let declaration = current.as(EnumDeclSyntax.self) {
        guard declaration.genericParameterClause == nil else { return false }
      } else if let declaration = current.as(ActorDeclSyntax.self) {
        guard declaration.genericParameterClause == nil else { return false }
      } else if let declaration = current.as(ClassDeclSyntax.self) {
        // A method of a class that is not final is dispatched dynamically, so the class must be final.
        guard declaration.genericParameterClause == nil, declaration.modifiers.contains(where: { $0.name.text == "final" }) else { return false }
      } else if let declaration = current.as(ExtensionDeclSyntax.self) {
        guard isPlainExtension(declaration) else { return false }
      }
      ancestor = current.parent
    }
    return true
  }

  /// An extension of a type written by its name alone (`Foo`, `Foo.Bar`, `Swift.Foo`), with no where clause, that the
  /// names set does not mark as generic, a protocol or a standard generic type.
  private func isPlainExtension(_ declaration: ExtensionDeclSyntax) -> Bool {
    guard declaration.genericWhereClause == nil, var components = Self.plainComponents(declaration.extendedType) else { return false }
    if components.count > 1, components.first == "Swift" { components.removeFirst() }
    if genericTypeNames.contains(components.joined(separator: ".")) { return false }
    for component in components {
      if genericTypeNames.contains(component) || ExportInterfaceTransform.standardGenericNames.contains(component)
        || component.hasPrefix("Unsafe")
      {
        return false
      }
    }
    return true
  }

  /// The name parts of an extended type with no generic arguments, or `nil` for any other type (an array, an optional, a
  /// tuple, a function type, or a generic instance).
  static func plainComponents(_ type: TypeSyntax) -> [String]? {
    if let identifier = type.as(IdentifierTypeSyntax.self), identifier.genericArgumentClause == nil {
      return [identifier.name.text]
    }
    if let member = type.as(MemberTypeSyntax.self), member.genericArgumentClause == nil, let base = plainComponents(member.baseType) {
      return base + [member.name.text]
    }
    return nil
  }
}

/// The names of the attributes of a list (`@name` and `@name(...)`), without their arguments. An `#if` block's attributes
/// are included.
private final class AttributeNameCollector: SyntaxVisitor {
  private(set) var names = Set<String>()

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
    names.insert(node.attributeName.trimmedDescription)
    return .skipChildren
  }
}
