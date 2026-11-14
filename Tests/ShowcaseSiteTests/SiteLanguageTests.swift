import Testing
@testable import ShowcaseSite

struct SiteLanguageTests {
  @Test func aPortugueseBrowserGetsPortuguese() {
    #expect(SiteLanguage.detect(preferred: ["pt-BR", "en"]) == .pt)
    #expect(SiteLanguage.detect(preferred: ["PT"]) == .pt)
  }

  @Test func anyOtherBrowserGetsEnglish() {
    #expect(SiteLanguage.detect(preferred: ["fr-FR"]) == .en)
    #expect(SiteLanguage.detect(preferred: []) == .en)
  }

  @Test func pickReturnsTheTextOfTheLanguage() {
    #expect(SiteLanguage.pt.pick(pt: "olá", en: "hello") == "olá")
    #expect(SiteLanguage.en.pick(pt: "olá", en: "hello") == "hello")
  }

  @Test func everyLanguageIsNamedInItself() {
    #expect(SiteLanguage.allCases.map(\.name) == ["Português", "English"])
  }
}
