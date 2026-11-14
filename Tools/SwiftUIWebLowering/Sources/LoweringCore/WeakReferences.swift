import SwiftParser
import SwiftSyntax

/// Embedded Swift has no weak references. The closure that held `self` weakly now holds it strongly, which is what the
/// task or callback it was written for does in a browser tab that lives as long as the page; the pass makes the three
/// spellings strong:
///
/// - `[weak self]` (alone in the capture list) becomes `[self]`. The `guard let self` that unwrapped it has nothing left
///   to unwrap and is dropped together with the line break after it, and `self?.` / `self?[` in the closure's body
///   become `self.` / `self[`. (The indentation before a dropped `guard`, and a `;` after it, stay as they were: the
///   previous lowerer leaves them and the golden comparison is byte for byte.)
/// - any other `weak x` capture becomes `x = Optional(x)`: the closure still sees an optional, it only keeps the object
///   alive. A capture that names its value, `weak x = value`, becomes `x = Optional(value)`.
/// - `weak var` loses `weak`.
///
/// Applied to application sources only. Origin (the previous, text-based lowerer): `lower_weak_self` and the `weak-capture` / `weak-property`
/// rules of `transform_detailed`, selected together as `weak`. Rules: `weak-self`, `weak-capture`, `weak-property`.
///
/// The previous rules read the text: `[weak self]` anywhere in a string literal is rewritten, the closure is "the nearest
/// `{` before the capture list", and `self?.` is replaced as a substring (`myself?.x` loses its `?` too). The tree
/// reads capture clauses, closures and optional chains, so none of that happens here.
public struct WeakReferenceTransform: SourceTransform {
  public let name = "weak"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("weak") else { return text }
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    var edits = EditSet()
    var strongSelf = 0
    var captures = 0
    var closures: [ClosureExprSyntax] = []

    for token in tree.tokens(viewMode: .sourceAccurate) where isWeak(token) {
      guard let previous = token.previousToken(viewMode: .sourceAccurate), previous.tokenKind == .leftSquare || previous.tokenKind == .comma,
        let name = token.nextToken(viewMode: .sourceAccurate), isCapturedName(name)
      else { continue }
      if previous.tokenKind == .leftSquare, name.tokenKind == .keyword(.self),
        let close = name.nextToken(viewMode: .sourceAccurate), close.tokenKind == .rightSquare
      {
        // `[weak self]`, whatever is between the brackets and the words.
        edits.add(TextEdit(start: previous.startOffset, end: close.endOffset, replacement: "[self]"))
        strongSelf += 1
        if let closure = owningClosure(of: token) { closures.append(closure) }
        continue
      }
      edits.add(captureEdit(weak: token, name: name))
      captures += 1
    }

    // The body of each closure that held `self` weakly. A closure nested in another one is read by both, and the edit
    // set keeps one edit per position.
    for closure in closures where closure.rightBrace.presence == .present {
      let finder = SelfUnwrapFinder(bytes: bytes)
      finder.walk(closure.statements)
      for edit in finder.edits { edits.add(edit) }
    }

    let properties = PropertyFinder()
    properties.walk(tree)
    for modifier in properties.modifiers {
      edits.add(propertyEdit(modifier, bytes: bytes))
    }

    guard !edits.isEmpty else { return text }
    counts.add("weak-self", strongSelf)
    counts.add("weak-capture", captures)
    counts.add("weak-property", properties.modifiers.count)
    return try apply(edits.sorted, to: text)
  }

  /// A `weak` that starts a capture: a keyword inside a capture clause, an identifier where the parser recovered a
  /// bracketed list that is no closure's.
  private func isWeak(_ token: TokenSyntax) -> Bool {
    token.tokenKind == .keyword(.weak) || token.tokenKind == .identifier("weak")
  }

  private func isCapturedName(_ token: TokenSyntax) -> Bool {
    if case .identifier = token.tokenKind { return true }
    return token.tokenKind == .keyword(.self)
  }

  /// `weak x` as `x = Optional(x)`, `weak x = value` as `x = Optional(value)`.
  private func captureEdit(weak token: TokenSyntax, name: TokenSyntax) -> TextEdit {
    let spelled = name.text
    if let capture = token.enclosing(ClosureCaptureSyntax.self), let initializer = capture.initializer {
      let value = initializer.value.trimmedDescription
      return TextEdit(start: token.startOffset, end: initializer.endOffset, replacement: "\(spelled) = Optional(\(value))")
    }
    return TextEdit(start: token.startOffset, end: name.endOffset, replacement: "\(spelled) = Optional(\(spelled))")
  }

  /// The closure whose capture clause holds `token`, nil for a `[weak self]` that is not part of a closure.
  private func owningClosure(of token: TokenSyntax) -> ClosureExprSyntax? {
    guard let clause = token.enclosing(ClosureCaptureClauseSyntax.self) else { return nil }
    return clause.enclosing(ClosureExprSyntax.self)
  }

  /// `weak var` as `var`: the modifier goes with the white space up to the next token.
  private func propertyEdit(_ modifier: DeclModifierSyntax, bytes: SourceBytes) -> TextEdit {
    let start = modifier.startOffset
    let end = modifier.endOffset
    guard let next = modifier.lastToken(viewMode: .sourceAccurate)?.nextToken(viewMode: .sourceAccurate) else { return .remove(start, end) }
    return bytes.isBlank(end, next.startOffset) ? .remove(start, next.startOffset) : .remove(start, end)
  }
}

private extension SyntaxProtocol {
  /// The nearest ancestor of a node type.
  func enclosing<Node: SyntaxProtocol>(_ type: Node.Type) -> Node? {
    var current = parent
    while let node = current {
      if let match = node.as(type) { return match }
      current = node.parent
    }
    return nil
  }
}

/// Edits keyed by their start offset, so the closures of a nest do not edit the same place twice. An edit inside the
/// range another one removes (a closure in the else block of a dropped `guard`) goes with it.
private struct EditSet {
  private var byStart: [Int: TextEdit] = [:]

  var isEmpty: Bool { byStart.isEmpty }
  var sorted: [TextEdit] {
    var kept: [TextEdit] = []
    for edit in byStart.values.sorted(by: { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }) {
      if let last = kept.last, edit.start < last.end { continue }
      kept.append(edit)
    }
    return kept
  }

  mutating func add(_ edit: TextEdit) {
    byStart[edit.start] = edit
  }
}

/// What a strong `self` makes redundant in a closure body: `guard let self else { … }` and the `?` of `self?.x`.
private final class SelfUnwrapFinder: SyntaxVisitor {
  private let bytes: SourceBytes
  private(set) var edits: [TextEdit] = []

  init(bytes: SourceBytes) {
    self.bytes = bytes
    super.init(viewMode: .sourceAccurate)
  }

  /// `guard let self else`, `guard let self = self else`: the only condition, and a `let`.
  override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
    guard node.conditions.count == 1,
      let binding = node.conditions.first?.condition.as(OptionalBindingConditionSyntax.self),
      binding.bindingSpecifier.tokenKind == .keyword(.let),
      binding.typeAnnotation == nil,
      let pattern = binding.pattern.as(IdentifierPatternSyntax.self), pattern.identifier.tokenKind == .keyword(.self),
      node.body.rightBrace.presence == .present
    else { return .visitChildren }
    if let initializer = binding.initializer {
      guard let reference = initializer.value.as(DeclReferenceExprSyntax.self), reference.baseName.tokenKind == .keyword(.self) else {
        return .visitChildren
      }
    }
    let start = node.startOffset
    var end = node.endOffset
    if end < bytes.bytes.count, bytes.bytes[end] == 0x0A { end += 1 }
    edits.append(.remove(start, end))
    return .skipChildren
  }

  /// `self?.x`, `self?[0]`.
  override func visit(_ node: OptionalChainingExprSyntax) -> SyntaxVisitorContinueKind {
    guard let reference = node.expression.as(DeclReferenceExprSyntax.self), reference.baseName.tokenKind == .keyword(.self),
      let parent = node.parent
    else { return .visitChildren }
    let continuesChain =
      parent.as(MemberAccessExprSyntax.self)?.base?.id == node.id || parent.as(SubscriptCallExprSyntax.self)?.calledExpression.id == node.id
    if continuesChain { edits.append(.remove(node.questionMark.startOffset, node.questionMark.endOffset)) }
    return .visitChildren
  }
}

/// The `weak` modifiers of `weak var` declarations.
private final class PropertyFinder: SyntaxVisitor {
  private(set) var modifiers: [DeclModifierSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    guard node.bindingSpecifier.tokenKind == .keyword(.var) else { return .visitChildren }
    for modifier in node.modifiers where modifier.name.tokenKind == .keyword(.weak) && modifier.detail == nil {
      modifiers.append(modifier)
    }
    return .visitChildren
  }
}
