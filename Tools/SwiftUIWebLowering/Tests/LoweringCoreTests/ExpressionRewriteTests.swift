import Testing

@testable import LoweringCore

@Suite struct ExpressionRewriteTests {
  @Test func errorMessagesLoseTheirInterpolation() {
    let result = lower(
      """
      let a = Text("Import failed: \\(error)")
      let b = "Export failed: \\(error)"
      let c = "Import failed: \\(error.localizedDescription)"
      let d = "Import failed: \\(error) twice"
      let e = #"Import failed: \\#(error)"#
      // "Import failed: \\(error)"

      """,
      rules: ["error-interpolation"]
    )
    #expect(result.text.contains("Text(\"Import failed\")"))
    #expect(result.text.contains("let b = \"Export failed\""))
    #expect(result.text.contains("\"Import failed: \\(error.localizedDescription)\""))
    #expect(result.text.contains("\"Import failed: \\(error) twice\""))
    #expect(result.text.contains("#\"Import failed: \\#(error)\"#"))
    #expect(result.text.contains("// \"Import failed: \\(error)\""))
    #expect(result.counts["transfer-error-interpolation"] == 1)
    #expect(result.counts["export-error-interpolation"] == 1)
  }

  @Test func errorMessagesAreRewrittenInTheFrameworkToo() {
    let pipeline = LoweringPipeline.standard.selecting(["error-interpolation"])!
    let result = lower(pipeline, "let a = \"Import failed: \\(error)\"\n", options: LoweringOptions(lowerCodable: false))
    #expect(result.text == "let a = \"Import failed\"\n")
  }

  @Test func querySortKeyPathsBecomeClosures() {
    let result = lower(
      """
      struct Library: View {
        @Query(sort: \\Item.timestamp) var items: [Item]
        @Query(sort: \\Item.owner.name, order: .reverse) var owners: [Item]
        @Query( sort:   \\Item.title ) var spaced: [Item]
        @Query(filter: #Predicate<Item> { $0.done }, sort: \\Item.title) var filtered: [Item]
        @Query(sort: [SortDescriptor(\\Item.title)]) var descriptors: [Item]
        @Query(sort: \\Item.tags[0]) var subscripted: [Item]
      }
      """,
      rules: ["query-sort-key-path"]
    )
    #expect(result.text.contains("@Query(sort: { (model: Item) in model.timestamp }) var items"))
    #expect(result.text.contains("@Query(sort: { (model: Item) in model.owner.name }, order: .reverse) var owners"))
    #expect(result.text.contains("@Query(sort: { (model: Item) in model.title } ) var spaced"))
    #expect(result.text.contains("sort: \\Item.title) var filtered"))
    #expect(result.text.contains("[SortDescriptor(\\Item.title)]"))
    #expect(result.text.contains("@Query(sort: \\Item.tags[0])"))
    #expect(result.counts["query-sort-key-path"] == 3)
  }

  @Test func defaultsCastsUseTypedReads() {
    let result = lower(
      """
      import Foundation
      func f(id: String) -> [String]? {
        UserDefaults.standard.array(forKey: "seen-\\(id)") as? [String]
      }
      let a = store.object(forKey: "flag") as? Bool
      let b = (store.object(forKey: key(for: "x")) as? Int) ?? 0
      let c = store.object(forKey: "d") as? Double ?? 1.5
      let d = store.object(forKey: "u") as? URL
      let e = store.object(forKey: "s") as! String
      let f = store.string(forKey: "s") as? String
      let g = store.object(forKey: key(a: (b))) as? String
      """,
      rules: ["defaults-object-cast"]
    )
    #expect(result.text.contains("._object(forKey: \"seen-\\(id)\", as: [String].self)"))
    #expect(result.text.contains("let a = store._object(forKey: \"flag\", as: Bool.self)"))
    #expect(result.text.contains("(store._object(forKey: key(for: \"x\"), as: Int.self)) ?? 0"))
    #expect(result.text.contains("store._object(forKey: \"d\", as: Double.self) ?? 1.5"))
    #expect(result.text.contains("as? URL"))
    #expect(result.text.contains("as! String"))
    #expect(result.text.contains("store.string(forKey: \"s\") as? String"))
    #expect(result.text.contains("let g = store._object(forKey: key(a: (b)), as: String.self)"))
    #expect(result.counts["defaults-object-cast"] == 5)
  }

  @Test func typeOfComparisonsBecomeCasts() {
    let result = lower(
      """
      func f(endpoint: Endpoint) -> Bool {
        if type(of: endpoint) == Oauth.self { return true }
        if ready && type(of: self.endpoint) != Network.Other.self || done { return false }
        let name = String(describing: type(of: endpoint))
        return type(of: endpoint) == (Oauth.self) || Swift.type(of: endpoint) == Oauth.self
      }
      """,
      rules: ["type-of-test"]
    )
    #expect(result.text.contains("if (endpoint is Oauth) { return true }"))
    #expect(result.text.contains("if ready && !(self.endpoint is Network.Other) || done { return false }"))
    #expect(result.text.contains("String(describing: type(of: endpoint))"))
    #expect(result.text.contains("type(of: endpoint) == (Oauth.self) || Swift.type(of: endpoint) == Oauth.self"))
    #expect(result.counts["type-of-test"] == 2)
  }

  @Test func environmentEntriesSpellOutTheirKey() {
    let result = lower(
      """
      extension EnvironmentValues {
        @Entry var accent: Color = .blue
        @Entry public var spacing: Double = 8
        @Entry var layout: Layout = Layout(
          columns: 2,
          gap: 4
        )
        @Entry var optional: Int?
      }
      """,
      rules: ["environment-entry"]
    )
    #expect(result.counts["environment-entry"] == 3)
    #expect(result.text.contains(
      "  private struct _EntryKey_accent: EnvironmentKey { static var defaultValue: Color { .blue } }\n  var accent: Color { get { self[_EntryKey_accent.self] } set { self[_EntryKey_accent.self] = newValue } }"
    ))
    #expect(result.text.contains("  public var spacing: Double { get { self[_EntryKey_spacing.self] }"))
    #expect(result.text.contains("static var defaultValue: Layout { Layout(\n    columns: 2,\n    gap: 4\n  ) } }"))
    #expect(result.text.contains("@Entry var optional: Int?"))
  }

  @Test func aTrailingCommentStaysAfterTheEntryProperty() {
    let result = lower("extension EnvironmentValues {\n  @Entry var accent: Color = .blue // brand\n}\n", rules: ["environment-entry"])
    #expect(result.text.contains("{ get { self[_EntryKey_accent.self] } set { self[_EntryKey_accent.self] = newValue } } // brand\n}"))
  }

  @Test func dataBridgesBecomeConversions() {
    let result = lower(
      """
      let data = buffer.storage as Data
      let other = payload as Data
      let kept = (payload as? Data)
      let call = make() as Data
      let optional = maybe?.storage as Data
      """,
      rules: ["as-data-bridge"]
    )
    #expect(result.text.hasPrefix("@_spi(Renderer) import WebFoundation\n"))
    #expect(result.text.contains("let data = Data(_bridging: buffer.storage)"))
    #expect(result.text.contains("let other = Data(_bridging: payload)"))
    #expect(result.text.contains("(payload as? Data)"))
    #expect(result.text.contains("make() as Data"))
    #expect(result.counts["as-data-bridge"] == 2)
  }

  @Test func theBridgingImportGainsTheRendererSPIOnAnExistingPlainImport() {
    let plain = lower("  import WebFoundation\nlet data = buffer as Data\n", rules: ["as-data-bridge"])
    #expect(plain.text == "  @_spi(Renderer) import WebFoundation\nlet data = Data(_bridging: buffer)\n")
    let aliased = lower("import Foundation\nlet data = buffer as Data\n", aliased: true, rules: ["as-data-bridge"])
    #expect(aliased.text == "@_spi(Renderer) import Foundation\nlet data = Data(_bridging: buffer)\n")
    let missing = lower("let data = buffer as Data\n", aliased: true, rules: ["as-data-bridge"])
    #expect(missing.text == "@_spi(Renderer) import Foundation\nlet data = Data(_bridging: buffer)\n")
    // An import that already has the SPI is kept as it is, and one with other attributes is not the plain import.
    let exposed = lower("@_spi(Renderer) import WebFoundation\nlet data = buffer as Data\n", rules: ["as-data-bridge"])
    #expect(exposed.text == "@_spi(Renderer) import WebFoundation\nlet data = Data(_bridging: buffer)\n")
    let exported = lower("@_exported import WebFoundation\nlet data = buffer as Data\n", rules: ["as-data-bridge"])
    #expect(exported.text.hasPrefix("@_spi(Renderer) import WebFoundation\n@_exported import WebFoundation\n"))
  }

  @Test func theCodableImportComesAfterTheBridgingImport() {
    let source = "struct Profile: Codable { let id: Int }\nlet data = buffer as Data\n"
    let result = lower(source, rules: ["embedded-codable", "as-data-bridge"])
    #expect(result.text.hasPrefix("import SwiftUIWeb\n@_spi(Renderer) import WebFoundation\n"))
    // An aliased application reaches the framework through `Foundation`, so the bridging import is enough.
    let aliased = lower(source, aliased: true, rules: ["embedded-codable", "as-data-bridge"])
    #expect(aliased.text.hasPrefix("@_spi(Renderer) import Foundation\n"))
    #expect(!aliased.text.contains("import SwiftUI"))
    #expect(aliased.counts["embedded-codable-import"] == nil)
  }

  @Test func errorDescriptionsBecomeFreeFunctionCallsOnlyOnErrorReceivers() {
    let result = lower(
      """
      let a = error.localizedDescription
      let b = controller.purchaseError?.errorDescription
      let c = unit.localizedDescription
      let d = loadFailure.localizedDescription
      let e = err.errorDescription
      let f = self.lastError.localizedDescription
      let g = result.error().localizedDescription
      let h = (error as NSError).localizedDescription
      let i = errors[0].localizedDescription
      let k = results.map { $0.error.localizedDescription }
      // error.localizedDescription
      let j = "error.localizedDescription"
      """,
      rules: ["error-description"]
    )
    #expect(result.text.contains("let a = _embeddedErrorDescription(error)\n"))
    #expect(result.text.contains("let b = _embeddedOptionalErrorDescription(controller.purchaseError)\n"))
    #expect(result.text.contains("let c = unit.localizedDescription\n"))
    #expect(result.text.contains("let d = _embeddedErrorDescription(loadFailure)\n"))
    #expect(result.text.contains("let e = _embeddedOptionalErrorDescription(err)\n"))
    #expect(result.text.contains("let f = _embeddedErrorDescription(self.lastError)\n"))
    #expect(result.text.contains("result.error().localizedDescription"))
    #expect(result.text.contains("(error as NSError).localizedDescription"))
    #expect(result.text.contains("errors[0].localizedDescription"))
    #expect(result.text.contains("results.map { _embeddedErrorDescription($0.error) }"))
    #expect(result.text.contains("// error.localizedDescription"))
    #expect(result.text.contains("\"error.localizedDescription\""))
    #expect(result.counts["error-description"] == 6)
  }

  @Test func errorDescriptionsAreRewrittenInTheFrameworkToo() {
    let pipeline = LoweringPipeline.standard.selecting(["error-description"])!
    let result = lower(pipeline, "let a = error.localizedDescription\n", options: LoweringOptions(lowerCodable: false))
    #expect(result.text == "let a = _embeddedErrorDescription(error)\n")
  }

  @Test func theWholePipelineIsIdempotent() {
    let source = """
      import Foundation
      @Model final class Note { var title = "" }
      #Preview { Text("p") }
      extension EnvironmentValues {
        @Entry var accent: Color = .blue
      }
      struct Library: View {
        @Query(sort: \\Note.title) var notes: [Note]
        var body: some View {
          Text("Import failed: \\(error)")
        }
        func load() throws {
          try Task.checkCancellation()
          #if os(macOS)
          let flag = defaults.object(forKey: "k") as? Bool
          #endif
          let isNote = type(of: value) == Note.self
          let data = buffer as Data
          let message = error.localizedDescription
        }
      }

      """
    let once = lower(source)
    let twice = lower(once.text)
    #expect(twice.text == once.text)
    #expect(twice.counts.isEmpty)
    for rule in [
      "model-macro", "preview-macro", "environment-entry", "query-sort-key-path", "transfer-error-interpolation",
      "task-check-cancellation", "os-macos-condition", "defaults-object-cast", "type-of-test", "as-data-bridge", "error-description",
    ] {
      #expect(once.counts[rule] == 1, "\(rule)")
    }
  }
}
