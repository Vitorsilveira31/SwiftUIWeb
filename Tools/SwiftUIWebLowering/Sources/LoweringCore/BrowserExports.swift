import SwiftParser
import SwiftSyntax

/// The browser host calls the application through `@_cdecl` entry points that start it, deliver events and read the
/// rendered HTML. A `@main struct App: BrowserApp` gets them appended to its file (`BrowserExportsTemplate`), once: a file
/// that already holds `embedded_browser_start` is left alone. Applied to every source, framework included.
///
/// Origin (the previous, text-based lowerer): `patch_browser_exports` and `browser_exports`. The previous pattern is
/// `@main struct Name: BrowserApp` with at most one access modifier and `BrowserApp` first among the conformances,
/// matched anywhere in the text, comments included; this one reads a struct declaration with the `@main` attribute that
/// conforms to `BrowserApp` (in any position, so `struct App: Sendable, BrowserApp` gets its exports too) and has no
/// generic parameters.
public struct BrowserExportsTransform: SourceTransform {
  public let name = "browser-exports"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("BrowserApp"), text.contains("@main"), !text.contains("embedded_browser_start") else { return text }
    let tree = Parser.parse(source: text)
    let finder = BrowserAppFinder()
    finder.walk(tree)
    guard let appType = finder.appType else { return text }
    counts.add("browser-reactor-entry-and-html-exports", 1)
    return text + BrowserExportsTemplate.exports(for: appType) + (options.liveLiteralsFile == nil ? "" : BrowserExportsTemplate.liveLiterals)
      + (options.developmentExports ? BrowserExportsTemplate.stateSave : "")
  }
}

private final class BrowserAppFinder: SyntaxVisitor {
  var appType: String?

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    guard appType == nil else { return .skipChildren }
    if node.genericParameterClause == nil, node.attributes.names.contains("main"), hasCleanHeader(node),
      inheritedNames(node.inheritanceClause).contains("BrowserApp")
    {
      appType = node.name.text
    }
    return .visitChildren
  }

  /// Whether nothing the parser could not read stands between the attributes and the `struct` keyword: a declaration
  /// recovered from broken text (`@main {access}struct App`) is not an application.
  private func hasCleanHeader(_ node: StructDeclSyntax) -> Bool {
    for child in node.children(viewMode: .sourceAccurate) {
      if child.is(UnexpectedNodesSyntax.self) { return false }
      if child.id == node.structKeyword.id { return true }
    }
    return true
  }
}
