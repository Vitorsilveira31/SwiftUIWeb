import SwiftParser
import SwiftSyntax

/// `@Entry var accent: Color = .blue` is a macro that declares an `EnvironmentKey`; the lowering spells out what it
/// expands to, a private key type holding the default and a property that reads and writes the environment through it.
/// The declaration needs a type and a default value, and only an access level of `public`, `internal` or `package`
/// between the attribute and `var`.
///
/// Origin (the previous, text-based lowerer): the `environment-entry` pattern of `transform_detailed`. The previous pattern takes the rest of the
/// line as the default value, so a trailing comment ends up inside the key type; here the value is the initializer
/// and a comment stays after the property.
public struct EnvironmentEntryTransform: SourceTransform {
  public let name = "environment-entry"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("@Entry") else { return text }
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    let finder = EntryFinder()
    finder.walk(tree)
    var edits: [TextEdit] = []
    for declaration in finder.entries {
      guard let attribute = declaration.attributes.last?.as(AttributeSyntax.self), attribute.attributeName.trimmedDescription == "Entry",
        attribute.arguments == nil, let indent = bytes.indentation(before: attribute.startOffset),
        declaration.bindingSpecifier.tokenKind == .keyword(.var), declaration.bindings.count == 1,
        let binding = declaration.bindings.first, let name = binding.pattern.as(IdentifierPatternSyntax.self),
        binding.accessorBlock == nil, let type = binding.typeAnnotation?.type, let initializer = binding.initializer
      else { continue }
      var access = ""
      if let modifier = declaration.modifiers.first {
        guard declaration.modifiers.count == 1, ["public", "internal", "package"].contains(modifier.name.text), modifier.detail == nil
        else { continue }
        access = modifier.name.text + " "
      }
      let key = name.identifier.text
      let typeName = type.trimmedDescription
      let value = initializer.value.trimmedDescription
      let keyType = "_EntryKey_\(key)"
      edits.append(TextEdit(
        start: attribute.startOffset, end: initializer.endOffset,
        replacement: "private struct \(keyType): EnvironmentKey { static var defaultValue: \(typeName) { \(value) } }\n"
          + "\(indent)\(access)var \(key): \(typeName) { get { self[\(keyType).self] } set { self[\(keyType).self] = newValue } }"
      ))
    }
    guard !edits.isEmpty else { return text }
    counts.add("environment-entry", edits.count)
    return try apply(edits, to: text)
  }
}

private final class EntryFinder: SyntaxVisitor {
  var entries: [VariableDeclSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.attributes.names.contains("Entry") { entries.append(node) }
    return .visitChildren
  }
}
