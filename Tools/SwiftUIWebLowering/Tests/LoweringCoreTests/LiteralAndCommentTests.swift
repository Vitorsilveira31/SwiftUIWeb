import Testing

@testable import LoweringCore

/// Text the rules must read as text (string literals, raw and multiline ones, interpolations, comments) and the code
/// around it. Every source ends in an observable class: it is lowered only if the lowerer found where the odd literal
/// or comment ends, and a declaration written inside one is left as written.
@Suite struct LiteralAndCommentTests {
  private static let model = "@Observable final class Model { var value = 1 }\n"
  private static let loweredModel = " final class Model { @Published(memberID: 1) var value = 1 }\n"

  /// The source lowered as an application, which must hold the odd text as it was and lower the class after it.
  private func expectModelLowered(_ prefix: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let output = lowered(prefix + Self.model)
    #expect(output.hasSuffix(prefix + Self.loweredModel), "\(output)", sourceLocation: sourceLocation)
  }

  @Test func delimitersInStringsNestedInAnInterpolationAreText() {
    expectModelLowered("let s = \"\\(table[\"{\"] ?? \")\")\"\nfunc f() { g() }\n")
  }

  @Test func anEscapedTripleQuoteDoesNotEndAMultilineString() {
    expectModelLowered("let s = \"\"\"\n  quote: \\\"\"\" {\n  \"\"\"\nfunc f() { }\n")
  }

  @Test func aMultilineInterpolationMayHoldStringsOfItsOwn() {
    expectModelLowered("let s = \"\"\"\n  \\(name ?? \"\"\"\n  }\n  \"\"\")\n  \"\"\"\nlet t = 1\n")
  }

  @Test func rawStringsInterpolateOnlyWithTheirHashes() {
    expectModelLowered("let s = #\"say \"hi\" \\#(f(\")\"))\"#\nlet t = 1\n")
    // With one hash only `\#(` interpolates; `\(` and a lone quote are content.
    expectModelLowered("let s = #\"a \\( \" b\"#\nlet t = (1)\n")
  }

  @Test func anInterpolationNestedInAnotherIsFollowedToItsEnd() {
    expectModelLowered("let s = \"a \\(f(\"b \\(g(\"}\")) c\")) d\"\nfunc f() { }\n")
  }

  @Test func commentsInsideAnInterpolationAreSkipped() {
    expectModelLowered("let s = \"\\(f(1) /* ) \" */ + g(2) // )\n)\"\nlet t = 1\n")
  }

  @Test func aRawMultilineStringHidesItsQuotesAndBraces() {
    expectModelLowered("let s = #\"\"\"\n  \"\"\" { \\(x) \"\n  \"\"\"#\nfunc f() { }\n")
  }

  @Test func blockCommentsNest() {
    expectModelLowered("/* outer /* inner */ still { comment */\nfunc f() { }\n")
  }

  @Test func aStringThatIsNotClosedEndsAtItsLine() {
    expectModelLowered("let s = \"abc { (\nlet t = (1)\n")
  }

  @Test func commentsStringsAndRawLiteralsAroundAClassAreKept() {
    let source = """
      // @Observable ignored
      let raw = #"#({ not a declaration })"#
      /* @Observable final class Blocked {} */
      let multiline = \"\"\"
      { still a string with accents: ação, lógica, matemática }
      \"\"\"
      @Observable final class Model { var value = 1 }

      """
    let output = lowered(source)
    #expect(output.contains("// @Observable ignored\n"))
    #expect(output.contains("#\"#({ not a declaration })\"#"))
    #expect(output.contains("/* @Observable final class Blocked {} */"))
    #expect(output.contains("{ still a string with accents: ação, lógica, matemática }"))
    #expect(output.hasSuffix(Self.loweredModel))
    #expect(lowered(output) == output)
  }

  @Test func aCompilationDirectiveIsCode() {
    let source = "#if DEBUG\nlet enabled = true\n#endif\n"
    #expect(lowered(source) == source)
  }

  @Test func aSourceThatEndsInsideTextIsReturnedAsItWas() {
    for source in [
      "", "// trailing comment", "/* block without close", "\"\"\"unterminated", "let value = #\"raw text with no matching delimiter",
    ] {
      #expect(lowered(source) == source, "\(source)")
    }
  }

  @Test func aDeclarationWrittenInsideATextIsNotLowered() {
    // An interpolation nested in a string, a nested block comment and an escaped triple quote.
    let sources = [
      "let s = \"\\(table[\"@Observable final class Hidden { var v = 0 }\"] ?? \"\")\"\n",
      "/* outer /* inner */ @Observable class Hidden {} */\n",
      "let s = \"\"\"\n  \\\"\"\" @Observable class Hidden {}\n  \"\"\"\n",
    ]
    for source in sources {
      #expect(lowered(source) == source, "\(source)")
      #expect(lowered(source + Self.model) == "@_spi(Renderer) import SwiftUIWeb\n" + source + Self.loweredModel, "\(source)")
    }
  }

  @Test func literalsAndCommentsKeepTheirTextWhenARewriteRemovesTheLineAroundThem() {
    // The observation import goes with its line; the literal and the comment around it stay as they are.
    let source = "let a = \"one\" // two\nimport Observation\nlet b = \"\"\"\nthree\n\"\"\"\n"
    #expect(lowered(source) == "let a = \"one\" // two\nlet b = \"\"\"\nthree\n\"\"\"\n")
  }

  @Test func stringsWithTheTextOfADeclarationDoNotCountAsOne() {
    let source = """
      struct Holder {
        let example = "@State private var ignored = 1"
        // @State private var alsoIgnored = 2
        @State private var real = 0
        var body: some View { Text("x") }
      }

      """
    let output = lowered(source)
    #expect(output.contains("let example = \"@State private var ignored = 1\""))
    #expect(output.contains("// @State private var alsoIgnored = 2"))
    #expect(output.contains("@State(memberID: \(stableStateMemberID("real"))) private var real = 0"))
  }

  @Test func aParenthesisInAStringOrCommentDoesNotEndAnArgumentList() {
    let result = lower("Text(\"x\").environment(\\.a, f(\")\", /* ) */ 1, // )\n  2))\n")
    #expect(result.text == "@_spi(Renderer) import SwiftUIWeb\nText(\"x\").modifier(EnvironmentOverride(apply: { $0.a = f(\")\", /* ) */ 1, // )\n  2) }))\n")
  }

  @Test func aCommentOrStringAfterAPropertyTypeIsNotItsInitializer() {
    let output = lowered(
      """
      @Observable final class Model {
        var title: String // default = "x"
        var other: Int
        var note: String // (see notes
        var count = 1
        var quoted: String = "("
      }

      """)
    #expect(output.contains("@Published(memberID: 1) var title: String // default = \"x\"\n"))
    #expect(output.contains("@Published(memberID: 2) var other: Int\n"))
    #expect(output.contains("@Published(memberID: 3) var note: String // (see notes\n"))
    #expect(output.contains("@Published(memberID: 4) var count = 1"))
    #expect(output.contains("@Published(memberID: 5) var quoted: String = \"(\""))
  }

  @Test func deterministicFixturesLowerAndStabilizeAcrossUnicodeAndCRLF() {
    // Unicode comments, raw strings and CRLF line ends around nested observable classes and Codable payloads: the
    // second pass changes nothing.
    for seed in 0..<64 {
      let source =
        "import Observation\r\n// comentário \(seed) 🧵\r\nlet raw = #\"{ seed: \(seed) }\"#\r\n"
        + "@Observable final class Model\(seed) {\r\n  var value: Int?\r\n  var title = \"linha \(seed)\\ntexto\"\r\n"
        + "  @Observable final class Child { var nested = \(seed) }\r\n}\r\nstruct Payload\(seed): Codable { let value: Int }\r\n"
      let first = lowered(source)
      #expect(lowered(first) == first, "seed \(seed) was not idempotent")
      #expect(first.contains("EmbeddedCodable"), "seed \(seed)")
      #expect(first.contains("@Published(memberID:"), "seed \(seed)")
    }
  }
}
