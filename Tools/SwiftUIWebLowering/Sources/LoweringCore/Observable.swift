import SwiftParser
import SwiftSyntax

/// `@Observable` classes become sets of `@Published(memberID:)` members, the form the Embedded runtime observes
/// (`Documentation/OBSERVATION_CONTRACT.md`): the attribute is removed, each stored `var` of the class gets
/// `@Published(memberID: n)` with `n` counting from 1 in declaration order, an optional one without a value gets
/// `= nil` (the wrapper has no default initializer), `@ObservationIgnored` is removed, and an initializer's assignment
/// to a lowered member that has no declared value initializes the wrapper itself (`_total = Published(wrappedValue: 1,
/// memberID: 1)`: a setter call would be rejected while other stored properties are still uninitialized).
///
/// A member stays as it is when it is `static` or `class`, computed, a `let`, `@ObservationIgnored`, or carries an
/// attribute on its line (`@MainActor var x = 0`, a property wrapper). An `@Observable` that is not a class the lowerer can
/// rewrite (a struct, an enum, an actor, a class whose braces do not close) fails the run with `SWUI-L001`, and an
/// initializer assignment whose value cannot be delimited with `SWUI-L002`.
///
/// Applies to every source, application or framework.
///
/// Origin (the previous, text-based lowerer): `lower_observable`, `publish_stored_properties`, `lower_published_init_assignments`,
/// `remove_observation_ignored`. Rules: `observable-attribute`, `observable-published`, `observation-ignored`.
public struct ObservableTransform: SourceTransform {
  public let name = "observable"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("@Observable") else { return text }
    let tree = Parser.parse(source: text)
    var lowering = ObservableLowering(text: text, tree: tree)
    let edits = try lowering.run()
    guard !edits.isEmpty else { return text }
    counts.add("observable-attribute", lowering.classes)
    counts.add("observable-published", lowering.published)
    counts.add("observation-ignored", lowering.ignored)
    return try apply(edits, to: text)
  }
}

/// The names of the `@Observable` classes a source declares, nested ones included.
enum ObservableTypeScan {
  /// `modelMacro`: the pipeline runs `model-macro`, so an `@Model` class is `@Observable` by the time the scan matters.
  static func names(in text: String, options: LoweringOptions, modelMacro: Bool) throws -> Set<String> {
    var source = text
    if modelMacro && options.lowerCodable {
      var scratch = RuleCounts()
      source = try ModelMacroTransform().transform(source, options: options, counts: &scratch)
    }
    return names(in: source)
  }

  static func names(in text: String) -> Set<String> {
    guard text.contains("@Observable") else { return [] }
    let finder = ObservableMarkerFinder()
    finder.walk(Parser.parse(source: text))
    return Set(finder.markers.compactMap { $0.classDeclaration?.name.text })
  }
}

// MARK: - Finding the declarations

/// An `@Observable` attribute and the declaration it is attached to.
struct ObservableMarker {
  let attribute: AttributeSyntax
  let declaration: DeclSyntax?

  var offset: Int { attribute.startOffset }

  /// The class the lowerer rewrites: a class whose braces are both written. The previous lowerer finds no matching brace
  /// for any other, so it fails the run for it.
  var classDeclaration: ClassDeclSyntax? {
    guard let declaration = declaration?.as(ClassDeclSyntax.self),
      declaration.memberBlock.leftBrace.presence == .present, declaration.memberBlock.rightBrace.presence == .present
    else { return nil }
    return declaration
  }

  var isLoweredClass: Bool { classDeclaration != nil }
}

private final class ObservableMarkerFinder: SyntaxVisitor {
  var markers: [ObservableMarker] = []
  var ignored: [AttributeSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
    switch node.attributeName.trimmedDescription {
    case "Observable":
      markers.append(ObservableMarker(attribute: node, declaration: Self.attachedDeclaration(of: node)))
    case "ObservationIgnored":
      ignored.append(node)
    default:
      break
    }
    return .visitChildren
  }

  /// The declaration whose attribute list holds `attribute`, also when the attribute is inside a conditional block
  /// of the list; nil for an attribute on a type or a parameter.
  private static func attachedDeclaration(of attribute: AttributeSyntax) -> DeclSyntax? {
    var node = attribute.parent
    while let current = node, !current.is(AttributeListSyntax.self) {
      guard current.is(IfConfigClauseSyntax.self) || current.is(IfConfigClauseListSyntax.self) || current.is(IfConfigDeclSyntax.self) else { return nil }
      node = current.parent
    }
    return node?.parent?.as(DeclSyntax.self)
  }
}

// MARK: - Lowering

private let accessModifiers: Set<Keyword> = [.private, .fileprivate, .internal, .public, .package]

struct ObservableLowering {
  let text: String
  let tree: SourceFileSyntax
  private let bytes: SourceBytes
  private let markers: [ObservableMarker]
  private let ignoredAttributes: [AttributeSyntax]

  private(set) var classes = 0
  private(set) var published = 0
  private(set) var ignored = 0
  private var loweredBodies: [Range<Int>] = []

  init(text: String, tree: SourceFileSyntax) {
    self.text = text
    self.tree = tree
    bytes = SourceBytes(text)
    let finder = ObservableMarkerFinder()
    finder.walk(tree)
    markers = finder.markers
    ignoredAttributes = finder.ignored
  }

  mutating func run() throws -> [TextEdit] {
    var edits = try lowerScope(0..<bytes.bytes.count)
    // `@ObservationIgnored` goes from the body of every lowered class, nested types and methods included.
    for attribute in ignoredAttributes where loweredBodies.contains(where: { $0.contains(attribute.startOffset) }) {
      var end = attribute.attributeName.endOffset
      while end < bytes.bytes.count, bytes.bytes[end] == 0x20 || bytes.bytes[end] == 0x09 { end += 1 }
      edits.append(.remove(attribute.startOffset, end))
      ignored += 1
    }
    return withoutEditsInsideReplacements(edits)
  }

  /// The markers that lie in `scope`, handled the way the previous lowerer's recursion does: the outermost lowered classes
  /// are lowered last to first, each one's body (a scope of its own) before the class itself, and an `@Observable`
  /// that is attached to anything else, or to a class the lowerer cannot rewrite, fails the run once the scope's
  /// classes are done.
  private mutating func lowerScope(_ scope: Range<Int>) throws -> [TextEdit] {
    let inScope = markers.filter { scope.contains($0.offset) }
    var outermost: [(marker: ObservableMarker, range: Range<Int>)] = []
    for marker in inScope where marker.isLoweredClass {
      if let last = outermost.last, last.range.contains(marker.offset) { continue }
      guard let declaration = marker.classDeclaration else { continue }
      outermost.append((marker, marker.offset..<declaration.memberBlock.rightBrace.startOffset))
    }
    var edits: [TextEdit] = []
    for (marker, _) in outermost.reversed() {
      guard let declaration = marker.classDeclaration else { continue }
      let body = declaration.memberBlock.leftBrace.endOffset..<declaration.memberBlock.rightBrace.startOffset
      edits += try lowerScope(body)
      edits += try lowerClass(declaration, marker: marker)
      loweredBodies.append(body)
    }
    if let unsupported = inScope.first(where: { marker in !marker.isLoweredClass && !outermost.contains { $0.range.contains(marker.offset) } }) {
      throw unsupportedDeclaration(unsupported)
    }
    return edits
  }

  private func unsupportedDeclaration(_ marker: ObservableMarker) -> LoweringError {
    let line = LoweringError.position(of: marker.offset, in: text).line
    let reason: String
    switch marker.declaration?.kind {
    case .structDecl, .enumDecl, .actorDecl, .protocolDecl, .extensionDecl:
      let described = Self.describe(marker.declaration)
      reason = "@Observable applies to classes, but line \(line) declares \(described); make it a class or remove @Observable"
    default:
      reason = "@Observable declaration at line \(line) uses syntax the lowerer cannot rewrite safely; simplify that class or move the code out of @Observable"
    }
    return LoweringError(code: "SWUI-L001", message: reason, offset: marker.offset)
  }

  /// `struct `Name``, as the previous lowerer words it.
  private static func describe(_ declaration: DeclSyntax?) -> String {
    if let declaration = declaration?.as(StructDeclSyntax.self) { return "struct `\(declaration.name.text)`" }
    if let declaration = declaration?.as(EnumDeclSyntax.self) { return "enum `\(declaration.name.text)`" }
    if let declaration = declaration?.as(ActorDeclSyntax.self) { return "actor `\(declaration.name.text)`" }
    if let declaration = declaration?.as(ProtocolDeclSyntax.self) { return "protocol `\(declaration.name.text)`" }
    if let declaration = declaration?.as(ExtensionDeclSyntax.self) { return "extension `\(extendedTypeName(declaration.extendedType))`" }
    return "a declaration"
  }

  // MARK: One class

  private mutating func lowerClass(_ declaration: ClassDeclSyntax, marker: ObservableMarker) throws -> [TextEdit] {
    var edits: [TextEdit] = [.remove(marker.attribute.startOffset, marker.attribute.endOffset)]
    classes += 1
    let members = flattenedMembers(declaration.memberBlock.members)
    var memberID = 0
    var uninitialized: [String: Int] = [:]
    for variable in members.compactMap({ $0.as(VariableDeclSyntax.self) }) {
      guard let publication = publication(of: variable) else { continue }
      memberID += 1
      published += 1
      edits.append(.insert("@Published(memberID: \(memberID)) ", at: publication.start))
      edits += publication.defaults.map { .insert(" = nil", at: $0) }
      if let name = publication.uninitializedName { uninitialized[name] = memberID }
    }
    if !uninitialized.isEmpty {
      let initializers = members.compactMap { $0.as(InitializerDeclSyntax.self) }
      for initializer in initializers {
        guard let body = initializer.body else { continue }
        edits += try publishedAssignments(in: initializer, body: body, members: uninitialized, class: declaration)
      }
    }
    return edits
  }

  /// Where a stored `var` is published, or nil when it stays as it is.
  private struct Publication {
    /// Where `@Published(memberID:)` goes: the first modifier on the line of `var`, or `var` itself.
    var start: Int
    /// Offsets after the type of each optional binding that has no value, where ` = nil` goes.
    var defaults: [Int]
    /// The name of a member that is declared with a type and no value, which an initializer then assigns.
    var uninitializedName: String?
  }

  private func publication(of variable: VariableDeclSyntax) -> Publication? {
    guard variable.bindingSpecifier.tokenKind == .keyword(.var) else { return nil }
    if variable.modifiers.contains(.static) || variable.modifiers.contains(.class) { return nil }
    let keywordStart = variable.bindingSpecifier.startOffset
    let lineStart = bytes.lineStart(keywordStart)
    // An attribute written on the line of `var` (`@MainActor var x = 0`, a property wrapper) keeps the property as it is;
    // the previous lowerer reads the segment of the line before `var` for an `@`. `@ObservationIgnored` keeps it out wherever
    // it is written: the previous lowerer publishes `@ObservationIgnored` on the line above its property, and removes the
    // attribute, which makes a property the author excluded observed.
    let attributed = variable.attributes.contains { $0.startOffset >= lineStart && $0.startOffset < keywordStart }
    let ignored = variable.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "ObservationIgnored" }
    if attributed || ignored { return nil }
    // A property is computed when an accessor block comes before any value (`var total: Int { a + b }`, `var x: Int`
    // followed by `willSet { … }`); a property with a value is stored, observers or not.
    var defaults: [Int] = []
    for binding in variable.bindings {
      if binding.initializer != nil { break }
      if binding.accessorBlock != nil { return nil }
    }
    for binding in variable.bindings where binding.initializer == nil && binding.accessorBlock == nil {
      // The wrapper has no default initializer, and Swift permits an uninitialized optional stored property, so the
      // equivalent `= nil` is supplied before wrapping it. A value is never invented for a non-optional one.
      if let annotation = binding.typeAnnotation, annotation.type.is(OptionalTypeSyntax.self) {
        defaults.append(annotation.endOffset)
      }
    }
    let first = variable.modifiers.map(\.startOffset).filter { $0 >= lineStart && $0 < keywordStart }.min() ?? keywordStart
    var uninitializedName: String?
    if variable.bindings.count == 1, let binding = variable.bindings.first, defaults.isEmpty,
      binding.initializer == nil, binding.accessorBlock == nil, binding.typeAnnotation != nil,
      let pattern = binding.pattern.as(IdentifierPatternSyntax.self), isPlainIdentifier(pattern.identifier.text),
      !pattern.identifier.text.hasPrefix("`"),
      variable.modifiers.allSatisfy({ modifier in
        if case .keyword(let keyword) = modifier.name.tokenKind { return accessModifiers.contains(keyword) }
        return false
      })
    {
      uninitializedName = pattern.identifier.text
    }
    return Publication(start: first, defaults: defaults, uninitializedName: uninitializedName)
  }

  // MARK: Initializer assignments

  /// Assignments in an initializer to a published member that has no declared value: `total = 1` and `self.total = 1`
  /// become `_total = Published(wrappedValue: 1, memberID: n)`.
  private func publishedAssignments(
    in initializer: InitializerDeclSyntax, body: CodeBlockSyntax, members: [String: Int], class declaration: ClassDeclSyntax
  ) throws -> [TextEdit] {
    let finder = AssignmentFinder(bytes: bytes, blockEnd: body.rightBrace.startOffset)
    finder.walk(body)
    // A bare name is the property only where no local or parameter of the initializer declares it: Swift resolves the bare
    // name to that declaration. `self.name` always names the property.
    var declared = LocalNameFinder.names(in: body)
    declared.formUnion(initializer.signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text })
    var edits: [TextEdit] = []
    var consumed = 0
    for assignment in finder.assignments {
      // An assignment in a closure or a nested function does not run as the initializer's own statement.
      guard !assignment.inClosure, let name = assignment.memberName, let memberID = members[name], assignment.start >= consumed else { continue }
      if assignment.isBareName && declared.contains(name) { continue }
      if assignment.valueIsIncomplete {
        throw LoweringError(
          code: "SWUI-L002",
          message:
            "cannot lower the assignment to `\(name)` in this initializer: its value does not end before the initializer body does; close its parentheses and brackets",
          offset: declaration.memberBlock.leftBrace.endOffset
        )
      }
      // A value that ends in a string literal or a comment continues on the next line, as the previous lowerer writes it.
      let separator = assignment.endsInLiteralOrComment ? "\n" : ""
      let value = bytes.slice(assignment.valueStart, assignment.valueEnd)
      edits.append(
        TextEdit(
          start: assignment.start, end: assignment.end,
          replacement: "_\(name) = Published(wrappedValue: \(value)\(separator), memberID: \(memberID))"
        ))
      consumed = assignment.end
    }
    return edits
  }
}

// MARK: - Assignments

/// An assignment statement `target = value`, with the extents the rewrites need.
struct AssignmentStatement {
  let node: SequenceExprSyntax
  /// `total` for `total = …` and `self.total = …`; nil for any other target.
  let memberName: String?
  let start: Int
  let valueStart: Int
  /// The end of the value: its last token, or the comment that follows it on the line.
  let valueEnd: Int
  /// The end of the value expression itself, before any comment.
  let expressionEnd: Int
  /// The end of the statement's text on its line.
  let end: Int
  let endsInLiteralOrComment: Bool
  let valueIsIncomplete: Bool
  /// The target is written as a bare name (`total`), not as `self.total`.
  let isBareName: Bool
  /// The statement is inside a closure or a nested function.
  let inClosure: Bool
}

final class AssignmentFinder: SyntaxVisitor {
  private(set) var assignments: [AssignmentStatement] = []
  private let bytes: SourceBytes
  private let blockEnd: Int?
  /// How many closures and nested functions the walk is inside.
  private var nestedDepth = 0

  /// `blockEnd`: the offset of the `}` that closes the initializer body being searched. The previous lowerer reads that
  /// body as a text of its own, so the end of the body ends the last line like a line break does.
  init(bytes: SourceBytes, blockEnd: Int? = nil) {
    self.bytes = bytes
    self.blockEnd = blockEnd
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
    nestedDepth += 1
    return .visitChildren
  }

  override func visitPost(_ node: ClosureExprSyntax) { nestedDepth -= 1 }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    nestedDepth += 1
    return .visitChildren
  }

  override func visitPost(_ node: FunctionDeclSyntax) { nestedDepth -= 1 }

  override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
    guard node.parent?.is(CodeBlockItemSyntax.self) == true else { return .visitChildren }
    let elements = Array(node.elements)
    guard elements.count >= 3, elements[1].is(AssignmentExprSyntax.self), let last = elements.last else { return .visitChildren }
    let value = elements[2]
    let lastToken = last.lastToken(viewMode: .sourceAccurate)
    var valueEnd = last.endOffset
    var commentEnd: Int?
    var cursor = last.endOffset
    for piece in lastToken?.trailingTrivia ?? [] {
      cursor += piece.sourceLength.utf8Length
      if piece.isComment { commentEnd = cursor }
    }
    if let commentEnd { valueEnd = commentEnd }
    let endsInString: Bool
    switch lastToken?.tokenKind {
    case .stringQuote?, .multilineStringQuote?, .rawStringPoundDelimiter?: endsInString = true
    default: endsInString = false
    }
    let incomplete = elements[2...].contains { element in
      element.tokens(viewMode: .all).contains { $0.presence == .missing }
    }
    assignments.append(
      AssignmentStatement(
        node: node,
        memberName: Self.memberName(of: elements[0]),
        start: node.startOffset,
        valueStart: value.startOffset,
        valueEnd: valueEnd,
        expressionEnd: last.endOffset,
        end: lineEnd(after: valueEnd),
        endsInLiteralOrComment: endsInString || commentEnd != nil,
        valueIsIncomplete: incomplete,
        isBareName: elements[0].is(DeclReferenceExprSyntax.self),
        inClosure: nestedDepth > 0
      ))
    return .visitChildren
  }

  /// The end of the statement's text: the spaces after it too when nothing else follows on its line (or the body ends),
  /// as the previous lowerer's line pattern drops them.
  private func lineEnd(after offset: Int) -> Int {
    var cursor = offset
    while cursor < bytes.bytes.count, bytes.bytes[cursor] == 0x20 || bytes.bytes[cursor] == 0x09 { cursor += 1 }
    guard cursor == bytes.bytes.count || cursor == blockEnd || bytes.bytes[cursor] == 0x0A || bytes.bytes[cursor] == 0x0D else { return offset }
    return cursor
  }

  /// `total` for `total` and `self.total`.
  static func memberName(of target: ExprSyntax) -> String? {
    if let reference = target.as(DeclReferenceExprSyntax.self), reference.argumentNames == nil { return reference.baseName.text }
    if let access = target.as(MemberAccessExprSyntax.self), access.declName.argumentNames == nil,
      let base = access.base?.as(DeclReferenceExprSyntax.self), base.baseName.tokenKind == .keyword(.self)
    {
      return access.declName.baseName.text
    }
    return nil
  }
}

/// The names an initializer body binds with `let`, `var`, `if let`, `guard let`, `for` or `case`. The closures and nested
/// functions in it have their own scopes, so their names are left out.
final class LocalNameFinder: SyntaxVisitor {
  private(set) var names: Set<String> = []

  init() { super.init(viewMode: .sourceAccurate) }

  static func names(in body: CodeBlockSyntax) -> Set<String> {
    let finder = LocalNameFinder()
    finder.walk(body)
    return finder.names
  }

  override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
    names.insert(node.identifier.text)
    return .skipChildren
  }

  override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

extension TriviaPiece {
  var isComment: Bool {
    switch self {
    case .lineComment, .blockComment, .docLineComment, .docBlockComment: true
    default: false
    }
  }
}

/// `edits` without the ones that lie inside a range another one replaces: the replaced text is rewritten whole, and an
/// edit inside it would overlap.
func withoutEditsInsideReplacements(_ edits: [TextEdit]) -> [TextEdit] {
  let replaced = edits.filter { $0.end > $0.start }
  return edits.filter { edit in
    !replaced.contains { other in
      other.start <= edit.start && edit.end <= other.end && (other.start < edit.start || edit.end < other.end)
    }
  }
}
