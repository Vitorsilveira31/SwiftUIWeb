import SwiftParser
import SwiftSyntax

/// `buffer as Data` is Foundation's NSMutableData/NSData bridging, which Embedded Swift has no runtime for; the
/// stand-in classes convert through `Data(_bridging:)`, which is the framework's `Renderer` SPI, so the file imports
/// the shim module it lives in with that SPI. An existing plain import of the module gains the SPI; otherwise the
/// import is added at the top. The operand must be a plain dotted name. Applied to application sources only.
///
/// Origin (the previous, text-based lowerer): the `as-data-bridge` pattern of `transform_detailed` and `expose_bridging_spi_import`.
public struct DataBridgeTransform: SourceTransform {
  public let name = "as-data-bridge"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("as Data") else { return text }
    let tree = Parser.parse(source: text)
    let finder = SequenceFinder()
    finder.walk(tree)
    var edits: [TextEdit] = []
    for sequence in finder.sequences {
      let elements = Array(sequence.elements)
      for index in 1..<max(elements.count - 1, 1) {
        guard let cast = elements[index].as(UnresolvedAsExprSyntax.self), cast.questionOrExclamationMark == nil,
          let type = elements[index + 1].as(TypeExprSyntax.self), type.trimmedDescription == "Data"
        else { continue }
        let operand = elements[index - 1]
        guard operand.is(DeclReferenceExprSyntax.self) || operand.is(MemberAccessExprSyntax.self),
          isDottedIdentifierPath(operand.trimmedDescription)
        else { continue }
        edits.append(TextEdit(
          start: operand.startOffset, end: type.endOffset,
          replacement: "Data(_bridging: \(operand.trimmedDescription))"
        ))
      }
    }
    guard !edits.isEmpty else { return text }
    counts.add("as-data-bridge", edits.count)
    return try Self.exposeBridgingSPI(apply(edits, to: text), aliased: options.moduleAliases)
  }

  /// The module `Data(_bridging:)` lives in: the shim, or `Foundation` for an application that aliases it.
  private static func exposeBridgingSPI(_ text: String, aliased: Bool) throws -> String {
    let module = aliased ? "Foundation" : "WebFoundation"
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    let finder = ImportFinder()
    finder.walk(tree)
    var edits: [TextEdit] = []
    for declaration in finder.imports where isPlainImport(declaration, of: module, bytes: bytes) {
      guard let indent = bytes.indentation(before: declaration.startOffset) else { continue }
      edits.append(TextEdit(
        start: bytes.lineStart(declaration.startOffset), end: declaration.endOffset,
        replacement: "\(indent)@_spi(Renderer) import \(module)"
      ))
    }
    if edits.isEmpty { return "@_spi(Renderer) import \(module)\n" + text }
    return try apply(edits, to: text)
  }

  /// `import Module` alone on its line, with or without `@_spi(Renderer)` in front.
  private static func isPlainImport(_ declaration: ImportDeclSyntax, of module: String, bytes: SourceBytes) -> Bool {
    guard declaration.modifiers.isEmpty, declaration.importKindSpecifier == nil, declaration.path.count == 1,
      declaration.path.first?.name.text == module
    else { return false }
    switch declaration.attributes.count {
    case 0:
      break
    case 1:
      guard let attribute = declaration.attributes.first?.as(AttributeSyntax.self), attribute.attributeName.trimmedDescription == "_spi",
        attribute.arguments?.trimmedDescription == "Renderer"
      else { return false }
    default:
      return false
    }
    return bytes.isBlank(declaration.endOffset, bytes.lineEnd(declaration.endOffset))
  }
}

private final class ImportFinder: SyntaxVisitor {
  var imports: [ImportDeclSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    imports.append(node)
    return .skipChildren
  }
}
