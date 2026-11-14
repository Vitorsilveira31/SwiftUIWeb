import SwiftParser
import SwiftSyntax

/// Adds `@_spi(Renderer)` to the SwiftUIWeb import of a lowered file when the file spells a Renderer SPI name. The
/// lowering emits `@State(memberID:)`, `@Published(memberID:)`, the `ForEach(_:id:)` and
/// `OutlineGroup(_:_embeddedChildren:)` closure initializers and `EnvironmentOverride`, which `.environment(\.key, value)`
/// becomes; none of them is public API, so a lowered file must see the SPI through its SwiftUIWeb import whichever rule
/// emitted the spelling. An import that already has the SPI is kept as it is. A file without the import is left alone
/// (framework sources reach the SPI from inside their own module, and an application source that uses the lowered
/// spelling already imports the framework), unless a rule of this run emitted the spelling: then the import is added at
/// the top.
///
/// The decision is made once, after every pass that can emit a spelling, so this pass runs after `view-inputs`.
///
/// Origin (the previous, text-based lowerer): `expose_lowered_renderer_spi`, `expose_renderer_spi_import`, `framework_import`. The previous pass looks
/// for the spellings and the import as text; this one reads tokens, so a spelling in a comment does not count, and the
/// import is found whatever follows it on its line (`import SwiftUIWeb // note`) and whatever its attributes are.
public struct RendererSPITransform: SourceTransform {
  public let name = "renderer-spi"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  /// The rules that emit a Renderer SPI spelling. A file that has the spelling only in its own source keeps the import
  /// it already has; a file a rule rewrote gains the import when it has none.
  private static let emittingRules = [
    "environment-modifier", "foreach-id-member", "foreach-id-self", "outline-children", "state-member-identities",
    "published-import",
  ]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard Self.mayContainSpelling(text) else { return text }
    let tree = Parser.parse(source: text)
    let scan = SPIScan()
    scan.walk(tree)
    guard scan.spellsRendererName(in: tree) else { return text }

    let modules: Set<String> = options.moduleAliases ? ["SwiftUI", "SwiftUIWeb"] : ["SwiftUIWeb"]
    let frameworkImports = scan.imports.filter { declaration in
      declaration.importKindSpecifier == nil && declaration.path.count == 1
        && declaration.path.first.map { modules.contains($0.name.text) } == true
    }
    if !frameworkImports.isEmpty {
      let edits = frameworkImports.compactMap { declaration -> TextEdit? in
        if declaration.attributes.trimmedDescription.contains("@_spi(Renderer)") { return nil }
        return TextEdit.insert("@_spi(Renderer) ", at: declaration.startOffset)
      }
      return try apply(edits, to: text)
    }
    guard Self.emittingRules.contains(where: { (counts[$0] ?? 0) > 0 }) else { return text }
    return "@_spi(Renderer) import \(options.moduleAliases ? "SwiftUI" : "SwiftUIWeb")\n" + text
  }

  /// Cheap pre-check before parsing: a file without any of the names cannot spell one.
  private static func mayContainSpelling(_ text: String) -> Bool {
    text.contains("memberID") || text.contains("_embeddedChildren") || text.contains("id:") || text.contains("EnvironmentOverride")
  }
}

private final class SPIScan: SyntaxVisitor {
  var imports: [ImportDeclSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    imports.append(node)
    return .skipChildren
  }

  /// Whether the code spells `memberID:`, `_embeddedChildren:`, `, id: {` or `EnvironmentOverride(`.
  func spellsRendererName(in tree: SourceFileSyntax) -> Bool {
    let tokens = Array(tree.tokens(viewMode: .sourceAccurate))
    for (index, token) in tokens.enumerated() {
      let next = index + 1 < tokens.count ? tokens[index + 1] : nil
      switch token.tokenKind {
      case .identifier("memberID"), .identifier("_embeddedChildren"):
        if next?.tokenKind == .colon { return true }
      case .identifier("EnvironmentOverride"):
        if next?.tokenKind == .leftParen { return true }
      case .comma:
        if index + 3 < tokens.count, tokens[index + 1].tokenKind == .identifier("id"), tokens[index + 2].tokenKind == .colon,
          tokens[index + 3].tokenKind == .leftBrace
        {
          return true
        }
      default:
        break
      }
    }
    return false
  }
}
