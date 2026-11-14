import Testing
@testable import Seekr

@MainActor
struct ResultsViewModelTests {
  @Test func aNewSearchLoadsTheFirstPageAndItsQuestions() async {
    let search = StubSearch()
    search.total = 25
    search.pages[1] = results(LiveWebRepository.pageSize)
    let questions = StubQuestions()
    questions.questions = ["Eum voluptas"]
    let model = SeekrResultsViewModel(searchWeb: search, searchNews: StubNews(), loadQuestions: questions)
    await model.run("harbor")
    #expect(search.requested == ["harbor:1"])
    #expect(questions.asked == ["harbor"])
    #expect(model.results.count == LiveWebRepository.pageSize)
    #expect(model.questions == ["Eum voluptas"])
    #expect(model.state == .loaded)
    #expect(model.pageCount == 3)
  }

  @Test func goingToAPageLoadsIt() async {
    let search = StubSearch()
    search.total = 25
    search.pages[2] = results(10, from: 11)
    let model = SeekrResultsViewModel(searchWeb: search, searchNews: StubNews(), loadQuestions: StubQuestions())
    await model.run("harbor")
    await model.goTo(2)
    #expect(model.page == 2)
    #expect(search.requested.last == "harbor:2")
    #expect(model.results.first?.id == 11)
  }

  @Test func aPageOutsideTheRangeIsIgnored() async {
    let search = StubSearch()
    search.total = 5
    let model = SeekrResultsViewModel(searchWeb: search, searchNews: StubNews(), loadQuestions: StubQuestions())
    await model.run("harbor")
    await model.goTo(0)
    await model.goTo(2)
    #expect(model.page == 1)
    #expect(search.requested == ["harbor:1"])
  }

  @Test func theNewsTabLoadsTheNewestFirstAndHasNoQuestions() async {
    let news = StubNews()
    news.total = 3
    news.pages[1] = results(3)
    let questions = StubQuestions()
    questions.questions = ["Eum voluptas"]
    let model = SeekrResultsViewModel(searchWeb: StubSearch(), searchNews: news, loadQuestions: questions)
    await model.run("harbor")
    await model.select(.news)
    #expect(model.tab == .news)
    #expect(news.requested == ["harbor:1"])
    #expect(model.results.count == 3)
    #expect(model.total == 3)
    #expect(questions.asked == ["harbor"])
  }

  @Test func theImagesTabLoadsNoResults() async {
    let search = StubSearch()
    let model = SeekrResultsViewModel(searchWeb: search, searchNews: StubNews(), loadQuestions: StubQuestions())
    await model.run("harbor")
    let before = search.requested
    await model.select(.images)
    #expect(model.tab == .images)
    #expect(search.requested == before)
  }

  @Test func aFailedSearchSaysItCouldNotReachTheService() async {
    let search = StubSearch()
    search.fails = true
    let model = SeekrResultsViewModel(searchWeb: search, searchNews: StubNews(), loadQuestions: StubQuestions())
    await model.run("harbor")
    #expect(model.state == .failed(FailureText.unreachable))
    search.fails = false
    await model.retry()
    #expect(model.state == .loaded)
  }

  @Test func aSearchWithNothingFoundHasNoPages() async {
    let model = SeekrResultsViewModel(searchWeb: StubSearch(), searchNews: StubNews(), loadQuestions: StubQuestions())
    await model.run("zzzz")
    #expect(model.results.isEmpty)
    #expect(model.pageCount == 1)
    #expect(model.state == .loaded)
  }
}
