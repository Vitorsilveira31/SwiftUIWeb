import Testing
@testable import Seekr

@MainActor
struct SuggestionsAndHomeTests {
  @Test func typingShowsTheSuggestionsForTheText() async {
    let stub = StubSuggestions()
    stub.answers["har"] = ["Harbor 1", "Harbor 2"]
    let model = SeekrSuggestionsViewModel(load: stub)
    await model.typed("har")
    #expect(model.suggestions == ["Harbor 1", "Harbor 2"])
  }

  @Test func clearingTheTextClearsTheSuggestions() async {
    let stub = StubSuggestions()
    stub.answers["har"] = ["Harbor 1"]
    let model = SeekrSuggestionsViewModel(load: stub)
    await model.typed("har")
    await model.typed("")
    #expect(model.suggestions.isEmpty)
    model.clear()
    #expect(model.suggestions.isEmpty)
  }

  @Test func aFirstResultOpensItsLink() async {
    let lucky = StubLucky()
    lucky.link = "https://anaalves.example.test/posts/4"
    let model = SeekrHomeViewModel(feelingLucky: lucky)
    #expect(await model.luckyLink(for: "harbor") == "https://anaalves.example.test/posts/4")
    #expect(model.notice == nil)
  }

  @Test func withoutAResultLuckySaysSo() async {
    let lucky = StubLucky()
    let model = SeekrHomeViewModel(feelingLucky: lucky)
    #expect(await model.luckyLink(for: "zzzz") == nil)
    #expect(model.notice == HomeStrings.noLuckyResult("zzzz"))
  }

  @Test func luckyWithoutTextDoesNothing() async {
    let model = SeekrHomeViewModel(feelingLucky: StubLucky())
    #expect(await model.luckyLink(for: "") == nil)
    #expect(model.notice == nil)
  }

  @Test func aFailedLuckySaysTheServiceCouldNotBeReached() async {
    let lucky = StubLucky()
    lucky.fails = true
    let model = SeekrHomeViewModel(feelingLucky: lucky)
    #expect(await model.luckyLink(for: "harbor") == nil)
    #expect(model.notice == FailureText.unreachable)
  }
}
