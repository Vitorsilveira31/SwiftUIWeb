import SwiftParser
import SwiftSyntax

/// SwiftUI keeps an `@Observable` reference in `@State` for the view's lifetime and observes the members each body
/// reads. The Embedded runtime models that retained reference with `StateObject`, so every `@State` whose declared type
/// or initializer is an observable class becomes `@StateObject` (`@State private var store = Store()`,
/// `@State var shared: Router`); value state keeps `@State`, and so does an optional model, which `StateObject` cannot
/// hold. A property's type decides, never its name. The initializer-side spellings follow: `_shared = State(wrappedValue:
/// router)` becomes `StateObject`, and `self.store = Store()` in an initializer, a setter call that Swift rejects while
/// other stored properties are uninitialized, becomes `_store = StateObject(wrappedValue: Store())`.
///
/// The observable classes are those of the whole package (`LoweringOptions.observableTypes`) and of the file itself.
/// Applies to every source, application or framework.
///
/// Origin (the previous, text-based lowerer): `lower_observable_state`. Rules: `state-observable-model`, `state-observable-init`,
/// `state-observable-assignment`.
public struct ObservableStateTransform: SourceTransform {
  public static let passName = "observable-state"
  public let name = ObservableStateTransform.passName

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  /// Access modifiers the previous lowerer's `@State` pattern accepts before `var`.
  private static let accepted: Set<Keyword> = [.private, .internal, .public, .fileprivate]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    let types = options.observableTypes
    guard !types.isEmpty, text.contains("State") else { return text }
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)

    // The declarations: the `@State` of a model becomes `@StateObject`, and its name is remembered.
    var edits: [TextEdit] = []
    var modelProperties = Set<String>()
    var models = 0
    tree.walkCode(variables: { variable in
      guard let model = Self.modelState(variable, types: types, bytes: bytes) else { return }
      edits.append(.insert("Object", at: model.attributeEnd))
      modelProperties.insert(model.name)
      models += 1
    })
    counts.add("state-observable-model", models)

    // `_name = State(wrappedValue: model)` initializes an observable property declared without a value, or constructs
    // an observable type directly.
    let finder = AssignmentFinder(bytes: bytes)
    finder.walk(tree)
    var initializers = 0
    for assignment in finder.assignments {
      guard let call = assignment.call(named: "State", bytes: bytes), let target = assignment.backingName else { continue }
      guard let first = call.firstArgumentIdentifier(bytes: bytes) else { continue }
      if modelProperties.contains(target) || types.contains(first) {
        edits.append(.insert("Object", at: call.callee.endOffset))
        // `State(initialValue:)` is the other spelling SwiftUI accepts; `StateObject` has only `wrappedValue:`.
        let labelStart = call.callee.endOffset + 1
        let labelEnd = labelStart + "initialValue".utf8.count
        if labelEnd < bytes.bytes.count, bytes.slice(call.callee.endOffset, labelEnd + 1) == "(initialValue:" {
          edits.append(TextEdit(start: labelStart, end: labelEnd, replacement: "wrappedValue"))
        }
        initializers += 1
      }
    }
    counts.add("state-observable-init", initializers)

    // `self.model = value` in an initializer initializes the wrapper itself.
    var assignedModels = 0
    if !modelProperties.isEmpty {
      let initializerFinder = InitializerBodyFinder()
      initializerFinder.walk(tree)
      for body in initializerFinder.bodies {
        let statements = AssignmentFinder(bytes: bytes, blockEnd: body.rightBrace.startOffset)
        statements.walk(body)
        var consumed = 0
        for assignment in statements.assignments {
          guard let name = assignment.memberName, modelProperties.contains(name), assignment.start >= consumed else { continue }
          let value = bytes.slice(assignment.valueStart, assignment.expressionEnd)
          let comment = assignment.valueEnd > assignment.expressionEnd ? bytes.slice(assignment.expressionEnd, assignment.valueEnd) : ""
          edits.append(
            TextEdit(
              start: assignment.start, end: assignment.end,
              replacement: "_\(name) = StateObject(wrappedValue: \(value))\(comment)"
            ))
          consumed = assignment.end
          assignedModels += 1
        }
      }
    }
    counts.add("state-observable-assignment", assignedModels)
    guard !edits.isEmpty else { return text }
    // An insertion inside a statement that is rewritten whole is part of its value.
    edits = withoutEditsInsideReplacements(edits)
    return try apply(edits, to: text)
  }

  struct ModelState {
    let name: String
    let attributeEnd: Int
  }

  /// A `@State var` whose type or initializer is one of `types`, read the way the previous lowerer's pattern reads
  /// `@State[ \t]+(access[ \t]+)?var[ \t]+name[ \t]*(: Type?)?(= Type\()?`.
  static func modelState(_ variable: VariableDeclSyntax, types: Set<String>, bytes: SourceBytes) -> ModelState? {
    guard let state = variable.attributes.last?.as(AttributeSyntax.self), state.attributeName.trimmedDescription == "State",
      state.arguments == nil, variable.bindingSpecifier.tokenKind == .keyword(.var), variable.modifiers.count <= 1
    else { return nil }
    if let modifier = variable.modifiers.first {
      guard modifier.detail == nil, case .keyword(let keyword) = modifier.name.tokenKind, accepted.contains(keyword) else { return nil }
      guard isHorizontalGap(bytes, modifier.endOffset, variable.bindingSpecifier.startOffset) else { return nil }
    }
    guard isHorizontalGap(bytes, state.endOffset, (variable.modifiers.first?.startOffset ?? variable.bindingSpecifier.startOffset)),
      let binding = variable.bindings.first, let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
      isPlainIdentifier(pattern.identifier.text)
    else { return nil }
    let name = pattern.identifier.text
    let isModel: Bool
    if let annotation = binding.typeAnnotation {
      let written = annotation.type.trimmedDescription
      let kind = identifierPathPrefix(written)
      isModel = !kind.isEmpty && types.contains(kind) && !written.dropFirst(kind.count).hasPrefix("?")
    } else if let initializer = binding.initializer {
      let written = initializer.value.trimmedDescription
      let kind = identifierPathPrefix(written)
      let rest = written.dropFirst(kind.count).drop { $0 == " " || $0 == "\t" }
      isModel = !kind.isEmpty && rest.hasPrefix("(") && types.contains(kind)
    } else {
      isModel = false
    }
    return isModel ? ModelState(name: name, attributeEnd: state.endOffset) : nil
  }

  private static func isHorizontalGap(_ bytes: SourceBytes, _ start: Int, _ end: Int) -> Bool {
    end > start && bytes.bytes[start..<end].allSatisfy { $0 == 0x20 || $0 == 0x09 }
  }
}

/// `[A-Za-z_][A-Za-z0-9_\.]*` at the start of `text`, or the empty string.
func identifierPathPrefix(_ text: String) -> String {
  guard text.isIdentifierStart else { return "" }
  return String(
    text.unicodeScalars.prefix { scalar in
      scalar == "_" || scalar == "." || (scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)))
    })
}

/// The bodies of every initializer in a file.
final class InitializerBodyFinder: SyntaxVisitor {
  private(set) var bodies: [CodeBlockSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    if let body = node.body { bodies.append(body) }
    return .visitChildren
  }
}

/// A call `State(…)` on the right of an assignment.
struct StateCall {
  let call: FunctionCallExprSyntax
  var callee: ExprSyntax { call.calledExpression }

  /// The identifier the previous lowerer's pattern reads after `State(` and an optional `wrappedValue:`: a model type
  /// (`State(wrappedValue: Store())`), a variable (`State(wrappedValue: router)`) or, when the argument starts with
  /// a label, the label itself.
  func firstArgumentIdentifier(bytes: SourceBytes) -> String? {
    guard let left = call.leftParen, let first = call.arguments.first else { return nil }
    let gap = bytes.bytes[left.endOffset..<first.startOffset]
    guard gap.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) else { return nil }
    let written = bytes.slice(first.startOffset, first.endOffset)
    if written.hasPrefix("wrappedValue:") {
      let rest = written.dropFirst("wrappedValue:".count).drop { $0 == " " || $0 == "\t" }
      let identifier = identifierPathPrefix(String(rest))
      if !identifier.isEmpty { return identifier }
    }
    let identifier = identifierPathPrefix(written)
    return identifier.isEmpty ? nil : identifier
  }
}

extension AssignmentStatement {
  /// The right-hand side as a call to `name` made with parentheses, when that is all it starts with.
  func call(named name: String, bytes: SourceBytes) -> StateCall? {
    let elements = Array(node.elements)
    guard let call = elements[2].as(FunctionCallExprSyntax.self), call.leftParen != nil,
      let callee = call.calledExpression.as(DeclReferenceExprSyntax.self), callee.baseName.text == name, callee.argumentNames == nil
    else { return nil }
    // `= State` and `State (` are separated by spaces and tabs only in the pattern.
    guard bytes.bytes[elements[1].endOffset..<call.startOffset].allSatisfy({ $0 == 0x20 || $0 == 0x09 }),
      bytes.bytes[callee.endOffset..<call.leftParen!.startOffset].allSatisfy({ $0 == 0x20 || $0 == 0x09 })
    else { return nil }
    return StateCall(call: call)
  }

  /// `name` for a target spelled `_name` or `self._name`: the property whose wrapper the assignment initializes.
  var backingName: String? {
    guard let spelled = memberName, spelled.hasPrefix("_"), spelled.count > 1 else { return nil }
    let name = String(spelled.dropFirst())
    return isPlainIdentifier(name) ? name : nil
  }
}
