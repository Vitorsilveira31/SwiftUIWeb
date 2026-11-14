import Testing

@testable import LoweringCore

@Suite struct PlatformRewriteTests {
  @Test func platformConditionsTakeTheMacOSSide() {
    let result = lower(
      """
      #if os(iOS)
      let layout = "phone"
      #elseif os(macOS)
      let layout = "desktop"
      #endif
      #if !os(macOS) && !os(iOS)
      let other = 1
      #endif
      let note = "os(macOS) in a string stays"
      // os(macOS) in a comment stays

      """,
      rules: ["os-macos-condition"]
    )
    #expect(result.text.contains("#elseif true\nlet layout = \"desktop\""))
    #expect(result.text.contains("#if !true && !os(iOS)"))
    #expect(result.text.contains("\"os(macOS) in a string stays\""))
    #expect(result.text.contains("// os(macOS) in a comment stays"))
    #expect(!result.text.contains("#elseif os(macOS)"))
    #expect(result.counts["os-macos-condition"] == 2)
  }

  @Test func aConditionWithTwoMacOSTermsCountsOnce() {
    let result = lower("#if os(macOS) || (os(macOS) && DEBUG)\nlet a = 1\n#endif\n", rules: ["os-macos-condition"])
    #expect(result.text == "#if true || (true && DEBUG)\nlet a = 1\n#endif\n")
    #expect(result.counts["os-macos-condition"] == 1)
  }

  @Test func theFrameworkKeepsItsPlatformConditions() {
    let source = "#if os(macOS)\nlet a = 1\n#endif\n"
    var pipeline = LoweringPipeline.standard
    pipeline = pipeline.selecting(["os-macos-condition"])!
    #expect(lower(pipeline, source, options: LoweringOptions(lowerCodable: false)).text == source)
  }

  @Test func checkCancellationBecomesTheEmbeddedSpelling() {
    let result = lower(
      """
      func work() async throws {
        try Task.checkCancellation()
        try Swift.Task.checkCancellation()
        // try Task.checkCancellation()
        let text = "Task.checkCancellation()"
        try Task<Void, Never>.checkCancellation()
      }

      """,
      rules: ["task-check-cancellation"]
    )
    #expect(result.text.contains("  try _embeddedCheckCancellation()\n"))
    #expect(result.text.contains("try Swift.Task.checkCancellation()"))
    #expect(result.text.contains("// try Task.checkCancellation()"))
    #expect(result.text.contains("\"Task.checkCancellation()\""))
    #expect(result.text.contains("try Task<Void, Never>.checkCancellation()"))
    #expect(result.counts["task-check-cancellation"] == 1)
  }

  @Test func swiftDataModelsBecomeObservablePersistentModels() {
    let result = lower(
      """
      @Model final class Note: Identifiable {
        var title: String
        init(title: String) { self.title = title }
      }
      @Model final class Tag {
        var name = ""
      }
      """,
      rules: ["model-macro"]
    )
    #expect(result.counts["model-macro"] == 2)
    #expect(result.text.contains("@Observable final class Note: Identifiable, PersistentModel {"))
    #expect(result.text.contains("@Observable final class Tag: PersistentModel {"))
    #expect(!result.text.contains("@Model"))
  }

  @Test func aModelAttributeOnItsOwnLineAndAGenericClassAreRead() {
    let result = lower(
      """
      @Model
      public final class Note: A,
        B
      {
        var title = ""
      }
      @Model final class Box<Value> { var value: Value? }
      let text = "@Model final class Fake {"
      """,
      rules: ["model-macro"]
    )
    #expect(result.counts["model-macro"] == 1)
    #expect(result.text.hasPrefix("@Observable\npublic final class Note: A,\n  B, PersistentModel\n{"))
    #expect(result.text.contains("@Model final class Box<Value>"))
    #expect(result.text.contains("\"@Model final class Fake {\""))
  }

  @Test func previewsAndPreviewProvidersAreRemovedWithTheirBodies() {
    let source = """
      struct ContentView: View {
        var body: some View { Text("a") }
      }
      #Preview {
        ContentView()
      }
      #Preview("Dark") { ContentView() }
      struct ContentView_Previews: PreviewProvider {
        static var previews: some View { ContentView() }
      }
      let after = 1

      """
    let result = lower(source, rules: ["preview-macro"])
    #expect(result.counts["preview-macro"] == 3)
    #expect(!result.text.contains("Preview"))
    #expect(result.text.contains("}\nlet after = 1"))
  }

  @Test func anUnterminatedPreviewAndOneThatDoesNotStartItsLineAreKept() {
    let unterminated = "#Preview {\n  ContentView()\n"
    #expect(lower(unterminated, rules: ["preview-macro"]).text == unterminated)
    let inline = "let a = 1; #Preview { Text(\"x\") }\n"
    #expect(lower(inline, rules: ["preview-macro"]).counts["preview-macro"] == nil)
  }

  @Test func aPreviewInsideAConditionalAndIndentedIsRemovedWithItsIndentation() {
    let result = lower(
      """
      #if DEBUG
        #Preview("Wide", traits: .landscapeLeft) {
          Text("a")
        }
      #endif

      """,
      rules: ["preview-macro"]
    )
    #expect(result.text == "#if DEBUG\n#endif\n")
    #expect(result.counts["preview-macro"] == 1)
  }

  @Test func aPreviewProviderTakesItsAttributesAndNestedPreviewsWithIt() {
    let result = lower(
      """
      @available(iOS 17, *)
      struct Card_Previews: PreviewProvider {
        static var previews: some View { Card() }
        struct Helper: View { var body: some View { Text("h") } }
      }
      struct Keep: View, PreviewProvider { var body: some View { Text("k") } }
      """,
      rules: ["preview-macro"]
    )
    #expect(result.counts["preview-macro"] == 1)
    #expect(result.text.hasPrefix("@available(iOS 17, *)\nstruct Card_Previews") == false)
    #expect(result.text.contains("struct Keep"))
  }

  @Test func aPreviewProviderWithItsBraceOnTheNextLineIsRemoved() {
    let result = lower("struct P_Previews : PreviewProvider\n{\n  static var previews: some View { Text(\"p\") }\n}\nlet after = 1\n", rules: ["preview-macro"])
    #expect(result.text == "let after = 1\n")
  }

  @Test func viewsNestedInAPreviewProviderAreRemovedBeforeTheyGetAComparison() {
    let source = """
      struct Card_Previews: PreviewProvider {
        struct Sample: View {
          let title: String
          var body: some View { Text(title) }
        }
        static var previews: some View { Sample(title: "a") }
      }
      struct Card: View {
        let title: String
        var body: some View { Text(title) }
      }

      """
    let result = lower(source, rules: ["preview-macro", "view-inputs"])
    #expect(!result.text.contains("Sample"))
    #expect(result.text.contains("extension Card {"))
    #expect(result.counts["view-input-comparison"] == 1)
  }
}
