import SwiftParser
import SwiftSyntax

/// A lowered `@Observable` class is a set of `@Published(memberID:)` members, which are the framework's `Renderer` SPI;
/// the file has to be able to name them. A file that spells one and imports none of the framework modules gains
/// `@_spi(Renderer) import SwiftUIWeb` (`SwiftUI` for an application that aliases it). A file whose code is wholly inside
/// one `#if` block (for example `#if !WEB`) gets the import inside each branch, so the browser build that compiles the
/// guarded branch still sees the module and the other builds never see a line outside the guard. Apple's Combine is never
/// injected; `CombineDiagnostics` rejects it in application sources.
///
/// Origin (the previous, text-based lowerer): the `published-import` step of `transform_detailed` and `file_wrapping_conditional_branches`. The
/// previous step read the lines of the text; this one reads the attribute and the import declarations, so an import with
/// two attributes (`@_spi(Renderer) @_spi(Generated) import SwiftUIWeb`) counts as an import, which the one-attribute
/// pattern of the previous step does not see (it adds a second import).
public struct PublishedImportTransform: SourceTransform {
  public let name = "published-import"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  /// The modules whose import makes `@Published(memberID:)` nameable: the framework under either name, SwiftData's
  /// shim (which re-exports it) and the Foundation shim.
  private static let importedModules: Set<String> = ["SwiftUIWeb", "SwiftUI", "SwiftData", "WebFoundation"]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("@Published") else { return text }
    let tree = Parser.parse(source: text)
    let scan = PublishedScan()
    scan.walk(tree)
    guard scan.spellsMemberID else { return text }
    if scan.imports.contains(where: Self.makesPublishedNameable) { return text }

    let line = "@_spi(Renderer) import \(options.moduleAliases ? "SwiftUI" : "SwiftUIWeb")"
    counts.add("published-import", 1)
    guard let headers = FileWrappingConditional.headerEnds(of: tree) else { return line + "\n" + text }
    let bytes = SourceBytes(text)
    return try apply(headers.map { TextEdit.insert("\n" + line, at: bytes.lineEnd($0)) }, to: text)
  }

  /// `import SwiftUI`, with or without attributes, a submodule path or an access modifier; not `import struct SwiftUI.X`,
  /// which names one declaration.
  private static func makesPublishedNameable(_ declaration: ImportDeclSyntax) -> Bool {
    declaration.importKindSpecifier == nil
      && declaration.path.first.map { importedModules.contains($0.name.text) } == true
  }
}

private final class PublishedScan: SyntaxVisitor {
  var spellsMemberID = false
  var imports: [ImportDeclSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
    if node.attributeName.trimmedDescription == "Published",
      case .argumentList(let arguments)? = node.arguments, arguments.first?.label?.text == "memberID"
    {
      spellsMemberID = true
    }
    return .visitChildren
  }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    imports.append(node)
    return .skipChildren
  }
}

/// A file whose code is one conditional block (`#if … #elseif … #else … #endif`) with nothing outside it.
///
/// Origin (the previous, text-based lowerer): `file_wrapping_conditional_branches`, which counts directive lines.
enum FileWrappingConditional {
  /// The offset just after the header of each branch (`#if`/`#elseif`/`#else` with its condition) of the block that
  /// wraps all of the file's code; nil when code lies outside such a block or the block is not closed.
  static func headerEnds(of tree: SourceFileSyntax) -> [Int]? {
    guard tree.statements.count == 1, case .decl(let declaration)? = tree.statements.first?.item,
      let block = declaration.as(IfConfigDeclSyntax.self), block.poundEndif.presence == .present
    else { return nil }
    return block.clauses.map { ($0.condition?.endOffset ?? $0.poundKeyword.endOffset) }
  }
}
