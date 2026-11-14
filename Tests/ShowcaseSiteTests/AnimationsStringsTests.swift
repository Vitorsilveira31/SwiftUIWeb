import Testing
@testable import ShowcaseSite

struct AnimationsStringsTests {
  @Test func everyDemoIsDescribedInBothLanguages() {
    for language in SiteLanguage.allCases {
      let demos = AnimationsStrings.all(language)
      #expect(demos.count == 8)
      for demo in demos {
        #expect(!demo.title.isEmpty && !demo.detail.isEmpty && !demo.code.isEmpty, "\(demo.id) in \(language)")
      }
    }
  }

  @Test func theDemosKeepTheirIdsAcrossLanguagesAndTheirIdsAreUnique() {
    let english = AnimationsStrings.all(.en).map(\.id)
    let portuguese = AnimationsStrings.all(.pt).map(\.id)
    #expect(english == portuguese)
    #expect(Set(english).count == english.count)
  }

  @Test func theWordsAreWrittenOncePerLanguage() {
    // The sentence is the part that is translated, and the code is not. A title may be the same in both: "Keyframes" is the
    // word Portuguese uses too.
    for (english, portuguese) in zip(AnimationsStrings.all(.en), AnimationsStrings.all(.pt)) {
      #expect(english.detail != portuguese.detail, "\(english.id) has one sentence for both languages")
      #expect(english.code == portuguese.code, "\(english.id) has two versions of its code")
    }
    #expect(AnimationsStrings.title(.en) == "Animations")
    #expect(AnimationsStrings.title(.pt) == "Animações")
  }

  @Test func theNamedModifierIsInTheCode() {
    // A card is about one API; its code has to show it.
    let named: [String: String] = [
      "numeric-text": "numericText", "transitions": "transition", "curves": "bouncy", "matched-geometry": "matchedGeometryEffect",
      "phase": "phaseAnimator", "keyframes": "keyframeAnimator", "symbol-effects": "symbolEffect", "progress-ring": "trim",
    ]
    for demo in AnimationsStrings.all(.en) {
      #expect(named[demo.id].map { demo.code.contains($0) } == true, "\(demo.id) does not show its API")
    }
  }

  @Test func everyPageHasATabTitleInBothLanguages() {
    for page in SitePage.allCases {
      for language in SiteLanguage.allCases { #expect(!ShellStrings.tab(page, language).isEmpty) }
    }
    #expect(SitePage.allCases.last == .animations)
  }
}
