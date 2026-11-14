import SwiftParser
import SwiftSyntax

/// One of the simple rewrites: it reads a tree and returns the edits to apply to the text it was parsed from.
struct SimpleRule: Sendable {
  /// The rule name the previous lowerer reports.
  let name: String
  /// A substring every text this rule can change contains, so a file that cannot hold the rule is not parsed for it.
  let needle: String
  /// Run again on its own output until it changes nothing: the edit replaces a region that may hold more of the same
  /// (`.environment(\.a, view.environment(\.b, 1))`), which one pass over the tree cannot rewrite in both places.
  var repeatsUntilStable = false
  /// The edits against `tree`, how many rewrites they stand for, and how many matches the rule declined and left as
  /// written (reported as `<name>-refused`).
  let edits: @Sendable (SourceFileSyntax, SourceBytes) -> (edits: [TextEdit], count: Int, refused: Int)

  init(
    _ name: String, needle: String, repeatsUntilStable: Bool = false,
    edits: @escaping @Sendable (SourceFileSyntax, SourceBytes) -> [TextEdit]
  ) {
    self.name = name
    self.needle = needle
    self.repeatsUntilStable = repeatsUntilStable
    self.edits = { tree, bytes in
      let found = edits(tree, bytes)
      return (found, found.count, 0)
    }
  }

  init(
    _ name: String, needle: String, repeatsUntilStable: Bool = false,
    counting edits: @escaping @Sendable (SourceFileSyntax, SourceBytes) -> (edits: [TextEdit], count: Int, refused: Int)
  ) {
    self.name = name
    self.needle = needle
    self.repeatsUntilStable = repeatsUntilStable
    self.edits = edits
  }
}

/// The key-path and spelling rewrites that need no state from the rest of the file: a key path argument becomes a
/// closure (`rows.map(\.name)`, `ForEach(rows, id: \.id)`), a projected value becomes a member binding
/// (`$model.label`), `@Environment(\.colorScheme)` and `.environment(\.colorScheme, .dark)` stop carrying a
/// `WritableKeyPath`, `ForEach(Mode.allCases)` gets an identity, `.onHover { hovered = $0 }` on a `@State` mirrors the
/// pointer without a closure, `@ContentBuilder` becomes `@ViewBuilder` and `import Observation` goes. The rules run
/// one after the other in the previous lowerer's order, each over the text the one before produced.
///
/// Origin (the previous, text-based lowerer): `apply_simple_rules`, `lower_environment_modifiers`, `lower_hover_assignments`.
public struct SimpleRulesTransform: SourceTransform {
  public let name = "simple-rules"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  static let rules: [SimpleRule] = [
    memberClosure("map-member", member: "map"),
    SimpleRule("binding-member", needle: "$", edits: bindingMemberEdits),
    SimpleRule("bindable-member", needle: "Bindable(", edits: bindableMemberEdits),
    SimpleRule("foreach-id-self", needle: "ForEach", edits: { forEachIdentityEdits($0, $1, selfOnly: true) }),
    SimpleRule("foreach-id-member", needle: "ForEach", edits: { forEachIdentityEdits($0, $1, selfOnly: false) }),
    SimpleRule("environment-member", needle: "Environment", edits: environmentMemberEdits),
    SimpleRule("outline-children", needle: "OutlineGroup", edits: outlineChildrenEdits),
    SimpleRule("keyframe-track", needle: "KeyframeTrack", edits: keyframeTrackEdits),
    SimpleRule("foreach-allcases-rawvalue", needle: "allCases", edits: forEachAllCasesEdits),
    memberClosure("compactMap-member", member: "compactMap"),
    memberClosure("flatMap-member", member: "flatMap"),
    memberClosure("filter-member", member: "filter"),
    memberClosure("allSatisfy-member", member: "allSatisfy"),
    memberClosure("mapValues-member", member: "mapValues"),
    memberClosure("compactMapValues-member", member: "compactMapValues"),
    memberClosure("forEach-member", member: "forEach"),
    SimpleRule("labeled-function-member", needle: "\\.", edits: labeledFunctionArgumentEdits),
    SimpleRule("content-builder-to-view-builder", needle: "ContentBuilder", edits: contentBuilderEdits),
    SimpleRule("table-column-value", needle: "TableColumn", edits: tableColumnValueEdits),
    SimpleRule("list-id-member", needle: "List", edits: listIdentityEdits),
    SimpleRule("environment-modifier", needle: ".environment", repeatsUntilStable: true, counting: environmentModifierEdits),
    SimpleRule("hover-assign", needle: "onHover", counting: hoverAssignEdits),
    SimpleRule("observation-import", needle: "Observation", edits: observationImportEdits),
  ]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    var text = text
    // The tree of `text`, kept while a rule that changed nothing leaves it as it was.
    var tree: SourceFileSyntax?
    for rule in Self.rules where text.contains(rule.needle) {
      repeat {
        let current = tree ?? Parser.parse(source: text)
        tree = current
        let found = rule.edits(current, SourceBytes(text))
        counts.add(rule.name, found.count)
        // A declined match is found again in every round, so it is counted once: in the round that changes nothing, or in
        // the only round of a rule that runs once.
        if found.edits.isEmpty || !rule.repeatsUntilStable { counts.add(rule.name + "-refused", found.refused) }
        guard !found.edits.isEmpty else { break }
        text = try apply(found.edits, to: text)
        tree = nil
        if !rule.repeatsUntilStable { break }
      } while true
    }
    return text
  }

  // MARK: Member calls

  /// `.map(\.name)` becomes `.map { $0.name }`: a key path as the one argument of a collection method.
  private static func memberClosure(_ rule: String, member: String) -> SimpleRule {
    SimpleRule(rule, needle: ".\(member)(", edits: { tree, _ in
      var edits: [TextEdit] = []
      tree.walkCode(calls: { call in
        guard memberCallName(call) == member, !call.hasTrailingClosure,
          let (leftParen, rightParen) = call.parentheses,
          call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
          let keyPath = PropertyKeyPath.rootless(argument.expression)
        else { return }
        edits.append(TextEdit(start: leftParen.startOffset, end: rightParen.endOffset, replacement: " { $0.\(keyPath.path) }"))
      })
      return edits
    })
  }

  /// Argument labels whose parameter is always a function in the standard library and SwiftUI: `split(whereSeparator:)`,
  /// `firstIndex(where:)`, `drop(while:)`, `Dictionary(grouping:by:)` and `partition(by:)`. A key path passed there
  /// becomes a closure. Every other label stays a key path: `id`, `value`, `using`, `sortUsing`, `keyPath`, `children`,
  /// `of` and the rest of the labels that take `KeyPath`s in SwiftUI, Charts and Observation, which the existing rules
  /// or the framework read as key paths. `by:` is listed because no standard-library or SwiftUI `by:` takes a key path
  /// (`sorted(by:)` takes two arguments, which a key path never matches).
  private static let functionArgumentLabels: Set<String> = ["whereSeparator", "where", "while", "by"]

  /// `text.split(whereSeparator: \.isNewline)` becomes `text.split(whereSeparator: { $0.isNewline })`. The call is left
  /// alone when it also takes another key path, since such a call belongs to a key-path API (`Table(rows, by: \.a, value: \.b)`).
  /// Only plain key paths are rewritten, as the member rules do: a root (`\Row.isOn`), optional chaining and subscripts
  /// stay key paths.
  private static func labeledFunctionArgumentEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(calls: { call in
      guard call.parentheses != nil else { return }
      let keyPathArguments = call.arguments.filter { $0.expression.is(KeyPathExprSyntax.self) }.count
      guard keyPathArguments == 1 else { return }
      for argument in call.arguments {
        guard let label = argument.label?.text, functionArgumentLabels.contains(label),
          let keyPath = PropertyKeyPath.rootless(argument.expression)
        else { continue }
        edits.append(TextEdit(
          start: argument.expression.startOffset, end: argument.expression.endOffset,
          replacement: "{ $0.\(keyPath.path) }"
        ))
      }
    })
    return edits
  }

  // MARK: Projected values

  /// `$model.label` becomes a binding that reads and writes the member through the model. A qualified projection
  /// (`Runtime.$value`, a task local) is a member access, not a view's binding, and `$flag.animation()` calls a
  /// Binding method, so only a member read of a projected name projects through the model. The binding establishes the
  /// member read while the declaring body owns the observation scope, as `Binding.dynamicMember` does; a getter-only
  /// rewrite would delay it into the retained control or child boundary.
  private static func bindingMemberEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(members: { access in
      guard let base = access.base?.as(DeclReferenceExprSyntax.self), base.argumentNames == nil else { return .visitChildren }
      let projected = base.baseName.text
      guard projected.hasPrefix("$"), isPlainIdentifier(String(projected.dropFirst())),
        access.declName.argumentNames == nil, isPlainIdentifier(access.declName.baseName.text)
      else { return .visitChildren }
      let end = access.endOffset
      if end < bytes.bytes.count && bytes.bytes[end] == UInt8(ascii: "(") { return .visitChildren }
      let model = String(projected.dropFirst())
      let member = access.declName.baseName.text
      edits.append(TextEdit(
        start: access.startOffset, end: end,
        replacement: "_memberBinding(get: { \(model).\(member) }, set: { \(model).\(member) = $0 })"
      ))
      return .skipChildren
    })
    return edits
  }

  /// `Bindable(model).label` makes the same binding as `$model.label`, so it takes the same lowered form. The model
  /// must be an identifier path (`model`, `self.model`, `store.session`), since the lowered closures repeat it. The
  /// member chain is taken from its outermost access; a member followed by a call (`Bindable(model).run()`) is left
  /// alone, and so is `Bindable(model)` without a member. A member of a chain that is itself called is still lowered
  /// (`Bindable(model).flag.animation()`), since `animation()` is a method of the `Binding` the member produces.
  private static func bindableMemberEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(members: { access in
      var path = [access.declName.baseName.text]
      var valid = access.declName.argumentNames == nil && isPlainIdentifier(path[0])
      var base = access.base
      while valid, let member = base?.as(MemberAccessExprSyntax.self) {
        valid = member.declName.argumentNames == nil && isPlainIdentifier(member.declName.baseName.text)
        path.insert(member.declName.baseName.text, at: 0)
        base = member.base
      }
      guard valid, let call = base?.as(FunctionCallExprSyntax.self), calleeName(call.calledExpression) == "Bindable",
        call.parentheses != nil, !call.hasTrailingClosure,
        call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
        isIdentifierPath(argument.expression)
      else { return .visitChildren }
      let end = access.endOffset
      if end < bytes.bytes.count && bytes.bytes[end] == UInt8(ascii: "(") { return .visitChildren }
      let target = ([argument.expression.trimmedDescription] + path).joined(separator: ".")
      edits.append(TextEdit(
        start: access.startOffset, end: end,
        replacement: "_memberBinding(get: { \(target) }, set: { \(target) = $0 })"
      ))
      return .skipChildren
    })
    return edits
  }

  /// `model`, `self.model`, `store.session`: identifiers joined by dots, with no call, subscript or argument label.
  private static func isIdentifierPath(_ expression: ExprSyntax) -> Bool {
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
      return reference.argumentNames == nil && isPlainIdentifier(reference.baseName.text)
    }
    if let access = expression.as(MemberAccessExprSyntax.self), let base = access.base {
      return access.declName.argumentNames == nil && isPlainIdentifier(access.declName.baseName.text) && isIdentifierPath(base)
    }
    return false
  }

  // MARK: Identities

  /// `ForEach(rows, id: \.self)` and `ForEach(rows, id: \.id)`: the key path that is the last argument becomes a
  /// closure.
  private static func forEachIdentityEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes, selfOnly: Bool) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(calls: { call in
      guard calleeName(call.calledExpression) == "ForEach", call.parentheses != nil,
        call.arguments.count >= 2, let identity = call.arguments.last, identity.label?.text == "id",
        let keyPath = PropertyKeyPath.rootless(identity.expression)
      else { return }
      guard (keyPath.members == ["self"]) == selfOnly else { return }
      let closure = selfOnly ? "{ $0 }" : "{ $0.\(keyPath.path) }"
      edits.append(TextEdit(start: identity.expression.startOffset, end: identity.expression.endOffset, replacement: closure))
    })
    return edits
  }

  /// `List(rows, id: \.id, selection: $selection)`: like `ForEach`, but the identity may be followed by more arguments,
  /// and `\.self` is the closure that returns the element.
  private static func listIdentityEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(calls: { call in
      guard calleeName(call.calledExpression) == "List", call.parentheses != nil else { return }
      let arguments = Array(call.arguments)
      guard arguments.count >= 2 else { return }
      for identity in arguments.dropFirst() where identity.label?.text == "id" {
        guard let keyPath = PropertyKeyPath.rootless(identity.expression) else { continue }
        let closure = keyPath.members == ["self"] ? "{ $0 }" : "{ $0.\(keyPath.path) }"
        edits.append(TextEdit(start: identity.expression.startOffset, end: identity.expression.endOffset, replacement: closure))
        break
      }
    })
    return edits
  }

  /// `ForEach(Mode.allCases) { … }` gets `id: { $0 }`: Embedded Swift cannot require `Identifiable` of the cases.
  private static func forEachAllCasesEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(calls: { call in
      guard calleeName(call.calledExpression) == "ForEach", let (_, rightParen) = call.parentheses,
        call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
        let access = argument.expression.as(MemberAccessExprSyntax.self), access.declName.baseName.text == "allCases",
        let base = access.base, isTypeName(base), let closure = call.trailingClosure,
        bytes.slice(rightParen.endOffset, closure.leftBrace.startOffset).allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\n" })
      else { return }
      edits.append(TextEdit(
        start: argument.expression.endOffset, end: closure.leftBrace.startOffset,
        replacement: ", id: { $0 }) "
      ))
    })
    return edits
  }

  /// `Mode`, `Module.Mode`: identifiers joined by dots.
  private static func isTypeName(_ expression: ExprSyntax) -> Bool {
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
      return reference.argumentNames == nil && isPlainIdentifier(reference.baseName.text)
    }
    if let access = expression.as(MemberAccessExprSyntax.self), let base = access.base {
      return access.declName.argumentNames == nil && isPlainIdentifier(access.declName.baseName.text) && isTypeName(base)
    }
    return false
  }

  /// `OutlineGroup(root, children: \.children)` takes the children through a closure.
  private static func outlineChildrenEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(calls: { call in
      guard calleeName(call.calledExpression) == "OutlineGroup", call.parentheses != nil,
        call.arguments.count == 2, let label = call.arguments.last?.label, label.text == "children",
        let children = call.arguments.last, let keyPath = PropertyKeyPath.rootless(children.expression), keyPath.members.count == 1
      else { return }
      edits.append(TextEdit(
        start: label.startOffset, end: children.expression.endOffset,
        replacement: "_embeddedChildren: { $0.\(keyPath.path) }"
      ))
    })
    return edits
  }

  /// `KeyframeTrack(\.x)` names the member and spells out the getter and the setter.
  private static func keyframeTrackEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(calls: { call in
      guard calleeName(call.calledExpression) == "KeyframeTrack", call.parentheses != nil,
        call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
        let keyPath = PropertyKeyPath.rootless(argument.expression), keyPath.members.count == 1
      else { return }
      let member = keyPath.path
      edits.append(TextEdit(
        start: argument.expression.startOffset, end: argument.expression.endOffset,
        replacement: "_embeddedMember: \"\(member)\", _embeddedGet: { $0.\(member) }, _embeddedSet: { $0.\(member) = $1 }"
      ))
    })
    return edits
  }

  // MARK: Tables

  /// `TableColumn("Name", value: \.name)` without a content closure shows the value as `Text`. (With a closure it is
  /// a sortable column, which the table-sorting pass has rewritten already.)
  private static func tableColumnValueEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(calls: { call in
      guard calleeName(call.calledExpression) == "TableColumn", let (leftParen, rightParen) = call.parentheses,
        call.arguments.count == 2, let title = call.arguments.first, title.label == nil, let comma = title.trailingComma,
        let value = call.arguments.last, value.label?.text == "value",
        let keyPath = PropertyKeyPath(value.expression), keyPath.members.count == 1
      else { return }
      let member = keyPath.path
      let row = keyPath.root.map { "(row: \($0))" } ?? "row"
      edits.append(TextEdit(
        start: leftParen.startOffset, end: rightParen.endOffset,
        replacement: "(\(bytes.slice(leftParen.endOffset, comma.startOffset))) { \(row) in Text(row.\(member)) }"
      ))
    })
    return edits
  }

  // MARK: Attributes

  /// `@Environment(\.colorScheme)` reads the environment through a closure.
  private static func environmentMemberEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(attributes: { attribute in
      guard attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Environment",
        case .argumentList(let arguments)? = attribute.arguments, arguments.count == 1,
        let argument = arguments.first, argument.label == nil,
        let keyPath = PropertyKeyPath(argument.expression), keyPath.members.count == 1,
        keyPath.root == nil || keyPath.root == "EnvironmentValues"
      else { return }
      edits.append(TextEdit(
        start: argument.expression.startOffset, end: argument.expression.endOffset,
        replacement: "_embedded: { $0.\(keyPath.path) }"
      ))
    })
    return edits
  }

  /// `@ContentBuilder` is the framework's spelling of `@ViewBuilder` in Embedded builds.
  private static func contentBuilderEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(attributes: { attribute in
      guard let name = attribute.attributeName.as(IdentifierTypeSyntax.self), name.name.text == "ContentBuilder",
        name.genericArgumentClause == nil
      else { return }
      edits.append(TextEdit(start: name.name.startOffset, end: name.name.endOffset, replacement: "ViewBuilder"))
    })
    return edits
  }

  // MARK: Environment overrides

  /// `.environment(\.colorScheme, .dark)` becomes a modifier that applies the same `EnvironmentValues` assignment,
  /// without carrying a `WritableKeyPath` into Embedded code. The object overload, `.environment(model)`, has no key
  /// path and is left alone.
  private static func environmentModifierEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> (edits: [TextEdit], count: Int, refused: Int) {
    var edits: [TextEdit] = []
    var refused = 0
    tree.walkCode(calls: { call in
      guard let access = call.calledExpression.as(MemberAccessExprSyntax.self), access.declName.baseName.text == "environment",
        access.declName.argumentNames == nil, !call.hasTrailingClosure,
        let (_, rightParen) = call.parentheses,
        let first = call.arguments.first, first.label == nil, let comma = first.trailingComma,
        let keyPath = PropertyKeyPath(first.expression),
        keyPath.root == nil || keyPath.root == "EnvironmentValues"
      else { return }
      let value = bytes.slice(comma.endOffset, rightParen.startOffset).trimmingWhitespace()
      guard !value.isEmpty else { return }
      // The value moves into a closure of its own, so a closure parameter it uses (`$0`) would be captured by that closure,
      // and a closure value would be nested in it. Such a call is left as written.
      if let valueExpression = call.arguments.last?.expression,
        valueExpression.is(ClosureExprSyntax.self) || ClosureParameterUseFinder.uses(in: valueExpression)
      {
        refused += 1
        return
      }
      // An override nested in this one's value is rewritten by the next round. A color scheme also marks its subtree
      // (`data-color-scheme`), which is what makes the semantic colors inside it resolve for that scheme.
      let replacement = keyPath.path == "colorScheme"
        ? ".modifier(EnvironmentOverride(colorScheme: \(value)))"
        : ".modifier(EnvironmentOverride(apply: { $0.\(keyPath.path) = \(value) }))"
      edits.append(TextEdit(start: access.period.startOffset, end: rightParen.endOffset, replacement: replacement))
    })
    let kept = outermost(edits)
    return (kept, kept.count, refused)
  }


  /// The edits that no other edit contains.
  private static func outermost(_ edits: [TextEdit]) -> [TextEdit] {
    var kept: [TextEdit] = []
    for edit in edits.sorted(by: { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }) {
      if let last = kept.last, edit.start < last.end { continue }
      kept.append(edit)
    }
    return kept
  }

  // MARK: Hover

  /// `.onHover { hovered = $0 }` on a `@State` of the same type only mirrors the pointer into state. It becomes
  /// `onHover(_assigning:)` so the renderer can learn the hovered look ahead of time and let the browser apply it in
  /// CSS. Any other closure body is left alone: it may do more than assign. The count is every
  /// `onHover(_assigning:` the file has afterwards, rewritten here or written that way.
  private static func hoverAssignEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> (edits: [TextEdit], count: Int, refused: Int) {
    // The `@State` names of each type, by the type that declares them: another type's `hovered` is a different property.
    var states: [String: Set<String>] = [:]
    var edits: [TextEdit] = []
    var written = 0
    tree.walkCode(
      calls: { call in
        if let (leftParen, _) = call.parentheses, memberCallName(call) == "onHover",
          call.arguments.first?.label?.text == "_assigning",
          leftParen.leadingTrivia.isEmpty, leftParen.trailingTrivia.isEmpty
        {
          written += 1
        }
      },
      variables: { variable in
        // `@State var name`, `@State(...) private var name`: the pattern the lowered `_name` storage exists for.
        guard variable.attributes.last?.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "State",
          variable.bindingSpecifier.tokenKind == .keyword(.var),
          variable.modifiers.count <= 1,
          variable.modifiers.allSatisfy({ $0.detail == nil && ($0.name.tokenKind == .keyword(.private) || $0.name.tokenKind == .keyword(.fileprivate)) }),
          let name = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
          let owner = enclosingTypeName(variable)
        else { return }
        states[owner, default: []].insert(name)
      }
    )
    tree.walkCode(calls: { call in
      guard let access = call.calledExpression.as(MemberAccessExprSyntax.self), access.declName.baseName.text == "onHover",
        access.declName.argumentNames == nil, call.leftParen == nil, call.arguments.isEmpty,
        call.additionalTrailingClosures.isEmpty, let closure = call.trailingClosure, closure.rightBrace.presence == .present,
        let target = hoverTarget(closure), let owner = enclosingTypeName(access), states[owner]?.contains(target) == true
      else { return }
      edits.append(TextEdit(
        start: access.period.startOffset, end: closure.rightBrace.endOffset,
        replacement: ".onHover(_assigning: _\(target))"
      ))
    })
    return (edits, written + edits.count, 0)
  }

  /// The name of the innermost type that holds `node`: a struct, class, enum, actor or protocol, or the type an extension
  /// extends. A `@State` is a member of the type that declares it, and `self` in a closure is that type.
  private static func enclosingTypeName(_ node: some SyntaxProtocol) -> String? {
    var current = node.parent
    while let candidate = current {
      if let declaration = candidate.as(StructDeclSyntax.self) { return declaration.name.text }
      if let declaration = candidate.as(ClassDeclSyntax.self) { return declaration.name.text }
      if let declaration = candidate.as(EnumDeclSyntax.self) { return declaration.name.text }
      if let declaration = candidate.as(ActorDeclSyntax.self) { return declaration.name.text }
      if let declaration = candidate.as(ProtocolDeclSyntax.self) { return declaration.name.text }
      if let declaration = candidate.as(ExtensionDeclSyntax.self) {
        return declaration.extendedType.as(IdentifierTypeSyntax.self)?.name.text ?? declaration.extendedType.trimmedDescription
      }
      current = candidate.parent
    }
    return nil
  }

  /// The state a hover closure assigns the pointer to: `{ hovered = $0 }`, `{ inside in hovered = inside }`, and
  /// either inside `withAnimation(…) { … }`.
  private static func hoverTarget(_ closure: ClosureExprSyntax) -> String? {
    var parameter: String?
    if let signature = closure.signature {
      guard signature.attributes.isEmpty, signature.capture == nil, signature.returnClause == nil,
        signature.effectSpecifiers == nil,
        case .simpleInput(let names)? = signature.parameterClause, names.count == 1, let name = names.first,
        isPlainIdentifier(name.name.text)
      else { return nil }
      parameter = name.name.text
    }
    guard closure.statements.count == 1, let statement = closure.statements.first?.item.as(ExprSyntax.self) else { return nil }
    if let assignment = pointerAssignment(statement, parameter: parameter) { return assignment }
    // `withAnimation { hovered = $0 }`, with arguments that are not closures.
    guard let animation = statement.as(FunctionCallExprSyntax.self), calleeName(animation.calledExpression) == "withAnimation",
      animation.additionalTrailingClosures.isEmpty, let inner = animation.trailingClosure,
      !animation.arguments.contains(where: { $0.trimmedDescription.contains("{") }),
      inner.signature == nil, inner.statements.count == 1,
      let assigned = inner.statements.first?.item.as(ExprSyntax.self)
    else { return nil }
    return pointerAssignment(assigned, parameter: parameter)
  }

  /// `name = $0` (or `name = parameter` when the closure names its parameter): the target `name`.
  private static func pointerAssignment(_ expression: ExprSyntax, parameter: String?) -> String? {
    guard let sequence = expression.as(SequenceExprSyntax.self), sequence.elements.count == 3 else { return nil }
    let elements = Array(sequence.elements)
    guard let target = elements[0].as(DeclReferenceExprSyntax.self), target.argumentNames == nil,
      isPlainIdentifier(target.baseName.text), elements[1].is(AssignmentExprSyntax.self),
      let value = elements[2].as(DeclReferenceExprSyntax.self), value.argumentNames == nil
    else { return nil }
    let assigned = value.baseName.text
    guard parameter.map({ assigned == $0 }) ?? (assigned == "$0") else { return nil }
    return target.baseName.text
  }

  // MARK: Imports

  /// `import Observation` goes: Embedded builds have the framework's own observation. The whole line is removed, so
  /// the import must be alone on its line.
  private static func observationImportEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(imports: { declaration in
      guard declaration.attributes.isEmpty, declaration.modifiers.isEmpty,
        declaration.importKindSpecifier == nil, declaration.path.count == 1, declaration.path.first?.name.text == "Observation"
      else { return }
      let lineStart = bytes.lineStart(declaration.startOffset)
      guard bytes.bytes[lineStart..<declaration.startOffset].allSatisfy({ $0 == 0x20 || $0 == 0x09 }) else { return }
      var end = declaration.endOffset
      while end < bytes.bytes.count && (bytes.bytes[end] == 0x20 || bytes.bytes[end] == 0x09) { end += 1 }
      guard end < bytes.bytes.count, bytes.bytes[end] == 0x0A else { return }
      edits.append(.remove(lineStart, end + 1))
    })
    return edits
  }
}

/// Whether an expression uses a closure parameter (`$0`...) that belongs to no closure inside the expression: the
/// parameters of a nested closure are its own.
private final class ClosureParameterUseFinder: SyntaxVisitor {
  private(set) var found = false

  init() { super.init(viewMode: .sourceAccurate) }

  static func uses(in expression: some SyntaxProtocol) -> Bool {
    let finder = ClosureParameterUseFinder()
    finder.walk(expression)
    return finder.found
  }

  override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    if case .dollarIdentifier = node.baseName.tokenKind { found = true }
    return .visitChildren
  }
}
