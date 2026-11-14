import SwiftParser
import SwiftSyntax

/// A `@State` property is identified by its position in the view, which changes when the view is re-created. A stable
/// member identity (`@State(memberID: 2901697652)`, FNV-1a of the property's name) lets the runtime keep the value
/// across re-creation (`StateStore.key(forMemberID:type:)`), so every `@State var name = …` that has a value gets one.
/// The id is inserted into the attribute: `@State` becomes `@State(memberID: n)`, `@State(wrappedValue: false)` becomes
/// `@State(wrappedValue: false, memberID: n)`. A property that already names a `memberID`, one without a value (its
/// initializer assigns the wrapper), a `let` and a tuple pattern are left alone, and `@StateObject` is a different
/// attribute (`observable-state` has already turned the models into it).
///
/// Applies to every source, application or framework.
///
/// Origin (the previous, text-based lowerer): `lower_state_member_ids`, `stable_state_member_id`. Rule: `state-member-identities`.
public struct StateMemberIDTransform: SourceTransform {
  public let name = "state-member-ids"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  /// Modifiers the previous lowerer's scan skips between `@State` and `var`.
  private static let skippedModifiers: Set<Keyword> = [
    .private, .fileprivate, .internal, .public, .open, .package, .static, .class, .final, .lazy, .weak, .unowned,
    .nonisolated, .override, .dynamic,
  ]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("@State") else { return text }
    let tree = Parser.parse(source: text)
    var edits: [TextEdit] = []
    tree.walkCode(variables: { variable in
      guard variable.bindingSpecifier.tokenKind == .keyword(.var),
        variable.modifiers.allSatisfy({ modifier in
          if case .keyword(let keyword) = modifier.name.tokenKind { return Self.skippedModifiers.contains(keyword) }
          return false
        }),
        let state = variable.attributes.compactMap({ $0.as(AttributeSyntax.self) }).first(where: { $0.attributeName.trimmedDescription == "State" }),
        let binding = variable.bindings.first, let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
      else { return }
      let arguments = state.arguments.map { $0.trimmedDescription } ?? ""
      if arguments.contains("memberID") { return }
      let hasWrappedValue = arguments.contains("wrappedValue")
      guard hasWrappedValue || variable.bindings.contains(where: { $0.initializer != nil }) else { return }
      let memberID = stableStateMemberID(pattern.identifier.text.trimmingBackticks())
      if let close = state.rightParen {
        let prefix = arguments.trimmingWhitespace().isEmpty ? "" : ", "
        edits.append(.insert("\(prefix)memberID: \(memberID)", at: close.startOffset))
      } else {
        edits.append(.insert("(memberID: \(memberID))", at: state.attributeName.endOffset))
      }
    })
    guard !edits.isEmpty else { return text }
    counts.add("state-member-identities", edits.count)
    return try apply(edits, to: text)
  }
}

/// FNV-1a of the name's UTF-8 bytes, never zero. FNV-1a rather than a `Hasher`, whose seed changes on every run: the
/// ids must be the same in every build and on every host.
func stableStateMemberID(_ name: String) -> UInt32 {
  var hash: UInt32 = 2_166_136_261
  for byte in name.utf8 {
    hash = (hash ^ UInt32(byte)) &* 16_777_619
  }
  return max(hash, 1)
}

extension String {
  fileprivate func trimmingBackticks() -> String {
    var text = self
    if text.hasPrefix("`") { text.removeFirst() }
    if text.hasSuffix("`") { text.removeLast() }
    return text
  }
}
