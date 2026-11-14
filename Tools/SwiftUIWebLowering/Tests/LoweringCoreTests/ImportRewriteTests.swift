import Testing

@testable import LoweringCore

@Suite struct ImportRewriteTests {
  /// What `@Observable final class Model { var value = 1 }` is lowered to by the observable pass.
  static let publishedClass = "final class Model {\n  @Published(memberID: 1) var value = 1\n}\n"

  // MARK: published-import

  @Test func thePublishedImportNamesSwiftUIWhenAliasedAndSwiftUIWebOtherwise() {
    let aliased = lower(Self.publishedClass, aliased: true, rules: ["published-import"])
    #expect(aliased.text == "@_spi(Renderer) import SwiftUI\n" + Self.publishedClass)
    #expect(aliased.counts["published-import"] == 1)

    let plain = lower(Self.publishedClass, rules: ["published-import"])
    #expect(plain.text.hasPrefix("@_spi(Renderer) import SwiftUIWeb\n"))
  }

  @Test func theImportAppliesToFrameworkSourcesToo() {
    let pipeline = LoweringPipeline.standard.selecting(["published-import"])!
    let result = lower(pipeline, Self.publishedClass, options: LoweringOptions(lowerCodable: false))
    #expect(result.text.hasPrefix("@_spi(Renderer) import SwiftUIWeb\n"))
  }

  @Test func theImportGoesInsideAFileWrappingConditionalBlock() {
    let guarded = "#if !WEB\n\(Self.publishedClass)#endif\n"
    let text = lowered(guarded, rules: ["published-import"])
    #expect(text == "#if !WEB\n@_spi(Renderer) import SwiftUIWeb\n\(Self.publishedClass)#endif\n")
  }

  @Test func theImportGoesIntoEveryBranchOfAGuardedFile() {
    let source = "#if !WEB\nlet tag = 1\n#else\n\(Self.publishedClass)#endif\n"
    let text = lowered(source, aliased: true, rules: ["published-import"])
    #expect(
      text
        == "#if !WEB\n@_spi(Renderer) import SwiftUI\nlet tag = 1\n#else\n@_spi(Renderer) import SwiftUI\n\(Self.publishedClass)#endif\n"
    )
  }

  @Test func theImportStaysOnLineOneForAnUnguardedFileAndIsIdempotent() {
    let guarded = "#if !WEB\n\(Self.publishedClass)#endif\n"
    for source in [Self.publishedClass, guarded] {
      let once = lowered(source, aliased: true, rules: ["published-import"])
      #expect(lowered(once, aliased: true, rules: ["published-import"]) == once)
    }
    #expect(lowered(Self.publishedClass, rules: ["published-import"]).hasPrefix("@_spi(Renderer) import SwiftUIWeb\nfinal class"))
  }

  @Test func anExistingFrameworkImportSuppressesThePublishedImport() {
    for existing in [
      "import SwiftUIWeb", "import SwiftUI", "import SwiftData", "import WebFoundation", "@_spi(Renderer) import SwiftUIWeb",
      "@_spi(Renderer) @_spi(Generated) import SwiftUIWeb", "import SwiftUI.Foo", "public import SwiftUIWeb",
    ] {
      let source = "\(existing)\n\(Self.publishedClass)"
      #expect(lowered(source, rules: ["published-import"]) == source, "\(existing)")
    }
    // An import of one declaration does not make `@Published` nameable.
    let narrow = "import struct SwiftUI.State\n\(Self.publishedClass)"
    #expect(lowered(narrow, rules: ["published-import"]) == "@_spi(Renderer) import SwiftUIWeb\n" + narrow)
  }

  @Test func onlyACodeSpellingOfThePublishedWrapperNeedsTheImport() {
    let notCode = "// @Published(memberID: 1) var value = 1\nlet plain = 1\n@Published var value = 1\n"
    #expect(lowered(notCode, rules: ["published-import"]) == notCode)
  }

  @Test func theWrappingBlockMustHoldAllOfTheCode() {
    func inserted(_ source: String) -> String { lowered(source, rules: ["published-import"]) }
    let import_ = "@_spi(Renderer) import SwiftUIWeb\n"
    let member = Self.publishedClass
    // Nested conditional blocks: the outer block's branch only.
    #expect(inserted("#if A\n#if B\n\(member)#endif\n#endif\n") == "#if A\n\(import_)#if B\n\(member)#endif\n#endif\n")
    // Code before or after the block, a block that is not closed, and a stray `#endif` leave the import on line one.
    #expect(inserted("let before = 1\n#if A\n\(member)#endif\n") == import_ + "let before = 1\n#if A\n\(member)#endif\n")
    #expect(inserted("#if A\n\(member)#endif\nlet after = 1\n") == import_ + "#if A\n\(member)#endif\nlet after = 1\n")
    #expect(inserted("#if A\n\(member)").hasPrefix(import_))
    // Comments around the block are not code.
    #expect(
      inserted("// header\n\n#if A\n\(member)#endif\n// footer\n")
        == "// header\n\n#if A\n\(import_)\(member)#endif\n// footer\n"
    )
  }

  // MARK: renderer-spi

  @Test func anImportGainsTheRendererSPIThroughTheFrameworkImport() {
    let imported = lowered(
      "import SwiftUIWeb\nText(\"Schedule\").environment(\\.timeZone, zone)\n", rules: ["simple-rules", "renderer-spi"]
    )
    #expect(imported.contains(".modifier(EnvironmentOverride(apply: { $0.timeZone = zone }))"))
    #expect(imported.contains("@_spi(Renderer) import SwiftUIWeb"))
    #expect(!imported.contains("\nimport SwiftUIWeb\n"))

    // A file that names the key path without any import gains the import the rewrite needs.
    let bare = lowered("let view = Text(\"Schedule\").environment(\\.timeZone, zone)", rules: ["simple-rules", "renderer-spi"])
    #expect(bare.hasPrefix("@_spi(Renderer) import SwiftUIWeb\n"))

    // An object overload is not rewritten, so it emits no SPI and the file gains none.
    let object = "import SwiftUIWeb\nText(\"Schedule\").environment(ThemeModel())\n"
    #expect(lowered(object, rules: ["simple-rules", "renderer-spi"]) == object)
  }

  @Test func theRendererSPIImportIsAddedOnceForEverySpellingTheLoweringEmits() {
    let text = lowered(
      """
      import SwiftUIWeb
      struct Probe: View {
        var body: some View {
          ForEach(items, id: \\.self) { item in Text(item) }
            .environment(\\.colorScheme, .dark)
        }
      }

      """
    )
    #expect(text.components(separatedBy: "@_spi(Renderer) import SwiftUIWeb").count == 2)
  }

  @Test func anAliasedTargetThatImportsSwiftUIWebByNameKeepsThatImport() {
    let body = "struct Probe: View {\n  @State(memberID: 7) private var selected = 0\n}\n"
    for existing in ["@_spi(Renderer) @_spi(Generated) import SwiftUIWeb", "@_spi(Renderer) import SwiftUIWeb"] {
      let text = lowered("\(existing)\n\(body)", aliased: true, rules: ["renderer-spi"])
      #expect(text == "\(existing)\n\(body)")
    }
    let plain = lowered("import SwiftUIWeb\n\(body)", aliased: true, rules: ["renderer-spi"])
    #expect(plain == "@_spi(Renderer) import SwiftUIWeb\n\(body)")
    // Another SPI on the import keeps its place after the added one.
    let generated = lowered("@_spi(Generated) import SwiftUIWeb\n\(body)", aliased: true, rules: ["renderer-spi"])
    #expect(generated == "@_spi(Renderer) @_spi(Generated) import SwiftUIWeb\n\(body)")
  }

  @Test func anAliasedTargetImportsTheAliasedModule() throws {
    let body = "struct Probe: View {\n  @State(memberID: 7) private var selected = 0\n}\n"
    let aliased = lowered("import SwiftUI\n\(body)", aliased: true, rules: ["renderer-spi"])
    #expect(aliased == "@_spi(Renderer) import SwiftUI\n\(body)")
    // Without the alias a SwiftUI import is Apple's: it is not the framework import.
    #expect(lowered("import SwiftUI\n\(body)", rules: ["renderer-spi"]) == "import SwiftUI\n\(body)")

    // The import is added only where a rule of this run emitted the spelling.
    var counts = RuleCounts()
    let transform = RendererSPITransform()
    let unemitted = try transform.transform(body, options: LoweringOptions(lowerCodable: true, moduleAliases: true), counts: &counts)
    #expect(unemitted == body)
    counts["state-member-identities"] = 1
    let emitted = try transform.transform(body, options: LoweringOptions(lowerCodable: true, moduleAliases: true), counts: &counts)
    #expect(emitted == "@_spi(Renderer) import SwiftUI\n\(body)")
    let plain = try transform.transform(body, options: LoweringOptions(lowerCodable: true), counts: &counts)
    #expect(plain == "@_spi(Renderer) import SwiftUIWeb\n\(body)")
  }

  @Test func onlyCodeSpellingsOfTheRendererNamesCount() {
    let comment = "import SwiftUIWeb\n// @State(memberID: 1) EnvironmentOverride(apply: {})\nlet x = 1\n"
    #expect(lowered(comment, rules: ["renderer-spi"]) == comment)
    for spelling in ["Probe(memberID: 3)", "Group(_embeddedChildren: { $0 })", "ForEach(rows, id: { $0 })", "EnvironmentOverride(apply: { _ in })"] {
      let text = lowered("import SwiftUIWeb\nlet v = \(spelling)\n", rules: ["renderer-spi"])
      #expect(text.hasPrefix("@_spi(Renderer) import SwiftUIWeb\n"), "\(spelling)")
    }
  }

  @Test func anImportKeepsItsPlaceWhateverFollowsItOnItsLine() {
    let source = "  import SwiftUIWeb // framework\nlet v = Probe(memberID: 3)\n"
    #expect(lowered(source, rules: ["renderer-spi"]) == "  @_spi(Renderer) import SwiftUIWeb // framework\nlet v = Probe(memberID: 3)\n")
    // Several imports of the framework (an aliased target and its shim) each gain the SPI once.
    let both = "import SwiftUI\nimport SwiftUIWeb\nlet v = Probe(memberID: 3)\n"
    #expect(
      lowered(both, aliased: true, rules: ["renderer-spi"])
        == "@_spi(Renderer) import SwiftUI\n@_spi(Renderer) import SwiftUIWeb\nlet v = Probe(memberID: 3)\n"
    )
    let once = lowered(both, aliased: true, rules: ["renderer-spi"])
    #expect(lowered(once, aliased: true, rules: ["renderer-spi"]) == once)
  }

  @Test func thePublishedImportIsTheSPIImportTheNextPassKeeps() {
    let text = lowered(Self.publishedClass, rules: ["published-import", "renderer-spi"])
    #expect(text == "@_spi(Renderer) import SwiftUIWeb\n" + Self.publishedClass)
  }
}
