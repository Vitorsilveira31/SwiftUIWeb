import Testing
@testable import Seekr

@MainActor
struct ShellViewModelTests {
  private func makeShell(search: StubSearch = StubSearch(), news: StubNews = StubNews()) -> SeekrShellViewModel {
    let results = SeekrResultsViewModel(searchWeb: search, searchNews: news, loadQuestions: StubQuestions())
    let images = SeekrImagesViewModel(searchPictures: StubPictures())
    let suggestions = SeekrSuggestionsViewModel(load: StubSuggestions())
    return SeekrShellViewModel(results: results, images: images, suggestions: suggestions)
  }

  @Test func aSubmittedSearchOpensTheResultsOfItsText() async {
    let search = StubSearch()
    search.total = 2
    search.pages[1] = results(2)
    let shell = makeShell(search: search)
    await shell.submit("harbor")
    #expect(shell.route == .results)
    #expect(shell.query == "harbor")
    #expect(search.requested == ["harbor:1"])
    #expect(shell.results.results.count == 2)
  }

  @Test func theRecentSearchesNewestFirstWithoutRepeats() async {
    let shell = makeShell()
    await shell.submit("harbor")
    await shell.submit("bread")
    await shell.submit("harbor")
    #expect(shell.recent == ["harbor", "bread"])
  }

  @Test func theRecentSearchesKeepSixAtMost() async {
    let shell = makeShell()
    for word in ["a", "b", "c", "d", "e", "f", "g"] {
      await shell.submit(word)
    }
    #expect(shell.recent == ["g", "f", "e", "d", "c", "b"])
  }

  @Test func anEmptySearchDoesNothing() async {
    let search = StubSearch()
    let shell = makeShell(search: search)
    await shell.submit("")
    #expect(shell.route == .home)
    #expect(search.requested.isEmpty)
    #expect(shell.recent.isEmpty)
  }

  @Test func editingKeepsTheTextAndGoingHomeShowsTheHomePage() async {
    let shell = makeShell()
    shell.edit("har")
    #expect(shell.query == "har")
    await shell.submit("harbor")
    shell.goHome()
    #expect(shell.route == .home)
  }
}
