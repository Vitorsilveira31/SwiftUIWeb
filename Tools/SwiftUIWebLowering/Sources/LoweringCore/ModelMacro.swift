import SwiftParser
import SwiftSyntax

/// SwiftData's `@Model` is a macro that makes a class observable and persistable; the browser stand-in keeps the
/// class observable and holds it in memory (see the SwiftData shim). `@Model final class Note { … }` becomes
/// `@Observable final class Note: PersistentModel { … }`, which the observable pass lowers like any other
/// `@Observable` class. A generic class is left alone, as the previous lowerer's pattern does not read one.
///
/// Origin (the previous, text-based lowerer): `model_macro_to_observable`.
public struct ModelMacroTransform: SourceTransform {
  public let name = "model-macro"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("@Model") else { return text }
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    let finder = ModelClassFinder()
    finder.walk(tree)
    var edits: [TextEdit] = []
    var models = 0
    for (declaration, attribute) in finder.models {
      guard declaration.genericParameterClause == nil, declaration.genericWhereClause == nil,
        declaration.memberBlock.leftBrace.presence == .present
      else { continue }
      edits.append(TextEdit(start: attribute.attributeName.startOffset, end: attribute.attributeName.endOffset, replacement: "Observable"))
      edits.append(conformanceEdit(declaration, bytes: bytes))
      models += 1
    }
    guard !edits.isEmpty else { return text }
    counts.add("model-macro", models)
    return try apply(edits, to: text)
  }

  /// Adds `PersistentModel` to the class's conformances. On the usual one-line header the text between the name and
  /// the brace is rewritten as `: A, B, PersistentModel ` like the previous pattern does; a header with a comment or a
  /// line break in it gets only the insertion.
  private func conformanceEdit(_ declaration: ClassDeclSyntax, bytes: SourceBytes) -> TextEdit {
    let nameEnd = declaration.name.endOffset
    let braceStart = declaration.memberBlock.leftBrace.startOffset
    let header = bytes.slice(nameEnd, braceStart)
    let plain = !header.contains("/") && !header.utf8.contains(0x0A)
    guard let clause = declaration.inheritanceClause else {
      return plain
        ? TextEdit(start: nameEnd, end: braceStart, replacement: ": PersistentModel ")
        : .insert(": PersistentModel", at: nameEnd)
    }
    if plain {
      let existing = clause.inheritedTypes.trimmedDescription
      return TextEdit(start: nameEnd, end: braceStart, replacement: ": \(existing), PersistentModel ")
    }
    return .insert(", PersistentModel", at: clause.inheritedTypes.endOffset)
  }
}

private final class ModelClassFinder: SyntaxVisitor {
  var models: [(ClassDeclSyntax, AttributeSyntax)] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    for element in node.attributes {
      if let attribute = element.as(AttributeSyntax.self), attribute.attributeName.trimmedDescription == "Model" {
        models.append((node, attribute))
        break
      }
    }
    return .visitChildren
  }
}
