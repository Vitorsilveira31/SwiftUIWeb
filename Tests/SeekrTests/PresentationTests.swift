import Testing
@testable import Seekr

struct PresentationTests {
  @Test func theWordsOfTheQueryAreBoldWhateverTheirPunctuationAndCase() {
    let runs = SnippetRuns.runs("Harbor lights glow, over the Harbor.", query: "harbor")
    #expect(runs.map(\.text) == ["Harbor", " ", "lights", " ", "glow,", " ", "over", " ", "the", " ", "Harbor."])
    #expect(runs.filter(\.isMatch).map(\.text) == ["Harbor", "Harbor."])
  }

  @Test func aSnippetWithoutTheQueryHasNoBoldRun() {
    let runs = SnippetRuns.runs("Bread rises slowly", query: "harbor")
    #expect(!runs.contains { $0.isMatch })
  }

  @Test func severalWordsOfTheQueryAreEachBold() {
    let runs = SnippetRuns.runs("bread and harbor", query: "harbor bread")
    #expect(runs.filter(\.isMatch).map(\.text) == ["bread", "harbor"])
  }

  @Test func thePagerCountsPagesAndKeepsOneAtLeast() {
    #expect(PageNumbers.count(total: 0, size: 10) == 1)
    #expect(PageNumbers.count(total: 10, size: 10) == 1)
    #expect(PageNumbers.count(total: 11, size: 10) == 2)
    #expect(PageNumbers.count(total: 100, size: 10) == 10)
  }

  @Test func thePagerOffersFiveNumbersAroundTheCurrentPage() {
    #expect(PageNumbers.window(current: 1, count: 1) == [1])
    #expect(PageNumbers.window(current: 1, count: 3) == [1, 2, 3])
    #expect(PageNumbers.window(current: 1, count: 10) == [1, 2, 3, 4, 5])
    #expect(PageNumbers.window(current: 5, count: 10) == [3, 4, 5, 6, 7])
    #expect(PageNumbers.window(current: 10, count: 10) == [6, 7, 8, 9, 10])
  }

  @Test func theCountSaysOneResultOrSeveral() {
    #expect(ResultsStrings.count(1) == "About 1 result")
    #expect(ResultsStrings.count(42) == "About 42 results")
  }
}
