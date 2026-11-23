import SwiftParser
import SwiftSyntax

/// Gives each of an application's views a comparison of its inputs (`View._comparesInputs`, `View._sameInputs`):
/// what its parent passed it, compared property by property with `_swiftUIWebSame`. The runtime then does not render
/// a view again while its inputs, the environment it read and its own state are unchanged, as SwiftUI does by
/// comparing a view's fields. A view nested in a private type, or one whose inputs cannot be compared, is left as it
/// was. Each extension follows the declaration at file scope that holds its view, so it sits in the same `#if`
/// branch; a view in another branch than the end of that declaration (an `#if` inside a type) is left as it was too.
///
/// Origin (the previous, text-based lowerer): `lower_view_input_comparisons`, `view_input_names`, `property_is_computed`.
public struct ViewInputComparisonTransform: SourceTransform {
  public let name = "view-inputs"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  /// Property wrappers whose reads the runtime already tracks (state, bindings and models through the state store,
  /// the environment by its entries): a view that compares its inputs leaves them out, and a change of what they
  /// hold renders the view again on its own.
  private static let trackedWrappers: Set<String> = [
    "State", "Binding", "Bindable", "Environment", "EnvironmentObject", "ObservedObject", "StateObject", "FocusState",
    "Namespace", "GestureState", "FocusedValue", "FocusedBinding", "FocusedObject", "ScaledMetric",
    "AccessibilityFocusState",
  ]

  /// Attributes on a stored property that do not change what it holds.
  private static let plainAttributes: Set<String> = ["ViewBuilder", "MainActor", "preconcurrency", "Sendable"]

  /// Modifiers the previous lowerer's declaration pattern accepts before `let`/`var`. A property with any other modifier
  /// (`weak`, `unowned`, `required`) is not read as an input at all.
  private static let acceptedModifiers: Set<Keyword> = [
    .public, .internal, .private, .fileprivate, .package, .nonisolated, .final, .override,
  ]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("View") else { return text }
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    let index = ScopeIndex(tree)
    // `stable-source-locations` may have put a directive inside the comparison this pass wrote earlier; the check below reads
    // the text without it, so that a second lowering finds the comparison and changes nothing.
    let plain = StableSourceLocationsTransform.strippingDirectives(text)

    var insertions: [(offset: Int, text: String)] = []
    for scope in index.scopes {
      guard let view = scope.node.as(StructDeclSyntax.self), ViewDeclarations.isView(view) else { continue }
      let path = scope.path
      // A nested private view is out of reach of an extension at file scope.
      if path.count > 1 && (view.modifiers.contains(.private) || view.modifiers.contains(.fileprivate)) { continue }
      // The members witness `View` requirements, so a public (or package) view needs them as visible as itself.
      let access = view.modifiers.lazy.compactMap { modifier -> String? in
        switch modifier.name.tokenKind {
        case .keyword(.public): "public "
        case .keyword(.package): "package "
        default: nil
        }
      }.first ?? ""
      // Lowering its own output changes nothing: a view whose comparison is in the file already keeps it.
      let qualified = path.joined(separator: ".")
      if plain.contains("extension \(qualified) {\n  \(access)static var _comparesInputs") { continue }
      // The declaration at file scope that holds the view (itself, when it is at file scope).
      guard let outer = ViewDeclarations.outermostScope(of: scope, in: index), outer.path.count == 1 else { continue }
      if ViewDeclarations.conditionalBranches(of: scope.node) != ViewDeclarations.conditionalBranches(of: outer.node) { continue }
      guard let names = inputNames(of: view, bytes: bytes) else { continue }
      let comparison = names.isEmpty
        ? "true"
        : names.map { "_swiftUIWebSame(lhs.\($0), rhs.\($0))" }.joined(separator: " && ")
      // After the line that closes the declaration.
      let insertion = bytes.lineEnd(outer.end) < bytes.bytes.count ? bytes.lineEnd(outer.end) + 1 : bytes.bytes.count
      insertions.append((
        insertion,
        "\nextension \(qualified) {\n  \(access)static var _comparesInputs: Bool { true }\n  \(access)static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { \(comparison) }\n}\n"
      ))
    }
    guard !insertions.isEmpty else { return text }
    counts.add("view-input-comparison", insertions.count)
    var edits = insertions.map { TextEdit.insert($0.text, at: $0.offset) }
    var output = text
    if output.utf8.last != 0x0A {
      // The newline is part of the text the insertions sit after.
      output.append("\n")
      edits = edits.map { TextEdit(start: min($0.start, output.utf8.count), end: min($0.end, output.utf8.count), replacement: $0.replacement) }
    }
    return try apply(edits, to: output)
  }

  /// The stored inputs of a view's body, or nil when the view cannot compare them: a property the runtime does not
  /// track (a storage wrapper, a custom wrapper, a `lazy` cache), a conditional block or a declaration of several
  /// names at once.
  private func inputNames(of view: StructDeclSyntax, bytes: SourceBytes) -> [String]? {
    var names: [String] = []
    for item in view.memberBlock.members {
      let member = item.decl
      if member.is(IfConfigDeclSyntax.self) { return nil }
      guard let variable = member.as(VariableDeclSyntax.self) else { continue }
      guard variable.modifiers.allSatisfy({ modifier in
        if case .keyword(let keyword) = modifier.name.tokenKind {
          return Self.acceptedModifiers.contains(keyword) || keyword == .static || keyword == .class || keyword == .lazy
        }
        return false
      }) else { continue }
      if variable.modifiers.contains(.static) || variable.modifiers.contains(.class) { continue }
      guard let binding = variable.bindings.first, let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
      if isComputed(binding) { continue }
      if variable.modifiers.contains(.lazy) || variable.bindings.count > 1 { return nil }
      var tracked = false
      for attribute in variable.attributes.names {
        let base = attribute.split(separator: "(").first.map(String.init) ?? attribute
        let name = base.split(separator: ".").last.map(String.init) ?? base
        if Self.trackedWrappers.contains(name) {
          tracked = true
        } else if !Self.plainAttributes.contains(name) {
          return nil
        }
      }
      if !tracked { names.append(identifier.identifier.text) }
    }
    return names
  }

  /// A property with a getter; observers on a stored property do not make it computed.
  private func isComputed(_ binding: PatternBindingSyntax) -> Bool {
    guard let block = binding.accessorBlock else { return false }
    switch block.accessors {
    case .getter:
      return true
    case .accessors(let accessors):
      return !accessors.allSatisfy { accessor in
        accessor.accessorSpecifier.tokenKind == .keyword(.willSet) || accessor.accessorSpecifier.tokenKind == .keyword(.didSet)
      }
    }
  }
}

/// What the passes that write an extension for each of an application's views (`view-inputs`, `state-installation`)
/// read of a view declaration.
enum ViewDeclarations {
  static func isView(_ declaration: StructDeclSyntax) -> Bool {
    guard let clause = declaration.inheritanceClause else { return false }
    return clause.inheritedTypes.contains { ["View", "SwiftUI.View", "SwiftUIWeb.View"].contains($0.type.trimmedDescription) }
  }

  /// The top-most type scope that holds `scope`, itself included.
  static func outermostScope(of scope: TypeScope, in index: ScopeIndex) -> TypeScope? {
    var result = scope
    var parent = scope.node.parent
    while let node = parent {
      if let enclosing = index.scope(of: node) { result = enclosing }
      parent = node.parent
    }
    return result
  }

  /// The `#if` branches that hold a node, outermost first: each `#if`, `#elseif` and `#else` is a branch of its own,
  /// so two nodes with the same branches are compiled together.
  static func conditionalBranches(of node: Syntax) -> [SyntaxIdentifier] {
    var branches: [SyntaxIdentifier] = []
    var parent = node.parent
    while let current = parent {
      if current.is(IfConfigClauseSyntax.self) { branches.append(current.id) }
      parent = current.parent
    }
    return branches.reversed()
  }

  /// The types, by their dotted name, that an extension in the file gives the method a pass writes: `func name()`, a
  /// member of the extension itself. A pass finds what it wrote in an earlier lowering this way: the declaration is the
  /// same whatever a later pass wrote before it, an attribute (`export-interface`) or a directive
  /// (`stable-source-locations`), while its text is not.
  ///
  /// What counts is what the text of the method counted, before the passes after it wrote into that text:
  /// - an extension of the whole type, as the passes write theirs: the type's name alone, with no generic arguments and no
  ///   where clause. Where the extension stands does not matter, a conditional block included;
  /// - a member of the extension, not one inside a conditional block of the extension: a configuration that leaves that
  ///   block out has no such method, so the pass still writes its own;
  /// - the method a pass writes and no other of that name (`isWritten(_:)`): another one stands beside it.
  static func typesExtended(withMethod name: String, in index: ScopeIndex) -> Set<String> {
    var types = Set<String>()
    for scope in index.scopes {
      let qualified = scope.path.joined(separator: ".")
      guard let declaration = scope.node.as(ExtensionDeclSyntax.self), declaration.genericWhereClause == nil,
        declaration.extendedType.trimmedDescription == qualified
      else { continue }
      if declares(name, in: declaration.memberBlock) { types.insert(qualified) }
    }
    return types
  }

  /// Whether `block` holds, as a member of its own, the method a pass writes as `func name()` (`isWritten(_:)`). The
  /// body of a type is asked too: a method declared there is the same declaration as one written in an extension.
  static func declares(_ name: String, in block: MemberBlockSyntax) -> Bool {
    block.members.contains { member in
      guard let function = member.decl.as(FunctionDeclSyntax.self) else { return false }
      // A name in backticks is the same name.
      var declared = Substring(function.name.text)
      if declared.count > 2, declared.first == "`", declared.last == "`" { declared = declared.dropFirst().dropLast() }
      return declared == name && isWritten(function)
    }
  }

  /// Whether `function` is the declaration a pass writes as `func name()`: a method of an instance with no parameter,
  /// generic parameter, constraint or result, and not `async`. One that differs in any of these (`static`, `async`,
  /// `where T: Equatable`, a result) is another declaration, which the written one can stand beside. `throws`,
  /// `mutating` and a result spelled `Void` make no other declaration: the compiler takes the written one for a second
  /// declaration of it.
  private static func isWritten(_ function: FunctionDeclSyntax) -> Bool {
    let signature = function.signature
    return signature.parameterClause.parameters.isEmpty && signature.effectSpecifiers?.asyncSpecifier == nil
      && (signature.returnClause.map { isVoid($0.type) } ?? true)
      && function.genericParameterClause == nil && function.genericWhereClause == nil
      && !function.modifiers.contains(.static) && !function.modifiers.contains(.class)
  }

  /// Whether `type` is `Void` as a result can spell it: `Void`, `Swift.Void`, `()`, or one of them in parentheses.
  private static func isVoid(_ type: TypeSyntax) -> Bool {
    if let tuple = type.as(TupleTypeSyntax.self) {
      if tuple.elements.isEmpty { return true }
      guard tuple.elements.count == 1, let only = tuple.elements.first, only.firstName == nil else { return false }
      return isVoid(only.type)
    }
    let name = type.trimmedDescription
    return name == "Void" || name == "Swift.Void"
  }
}
