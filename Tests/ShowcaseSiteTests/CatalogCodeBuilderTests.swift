import Testing
@testable import ShowcaseSite

struct CatalogCodeBuilderTests {
  @Test func aComponentIsFollowedByOneIndentedModifierPerLine() {
    var code = CatalogCodeBuilder("Text(\"Hi\")")
    code.modifier("font(.title)")
    code.modifier("bold()")
    #expect(code.text == "Text(\"Hi\")\n  .font(.title)\n  .bold()")
  }

  @Test func aConditionalModifierIsLeftOutWhenTheConditionIsFalse() {
    var code = CatalogCodeBuilder("Button(\"Go\") { }")
    code.modifier("disabled(true)", if: false)
    #expect(code.text == "Button(\"Go\") { }")
  }

  @Test func aLiteralEscapesQuotesAndBackslashes() {
    #expect(CatalogCodeBuilder.literal("say \"hi\" \\ bye") == "\"say \\\"hi\\\" \\\\ bye\"")
  }

  @Test func aLiteralCanEndInAnInterpolation() {
    #expect(CatalogCodeBuilder.literal("Guests: ", endingWith: "count") == "\"Guests: \\(count)\"")
  }

  @Test func wholeNumbersLoseTheirDecimalPoint() {
    #expect(CatalogCodeBuilder.number(8) == "8")
    #expect(CatalogCodeBuilder.number(0.5) == "0.5")
  }
}
