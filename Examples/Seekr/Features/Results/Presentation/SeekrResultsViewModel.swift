import SwiftUIWeb

/// The results of the submitted search, on the tab the reader has open: All (the pages of matching posts, with the questions) or News
/// (the newest first). Images have their own view model.
@MainActor @Observable
final class SeekrResultsViewModel {
  private(set) var query = ""
  private(set) var tab = SeekrTab.all
  private(set) var page = 1
  private(set) var state: LoadState = .loading
  private(set) var results: [SeekrResult] = []
  private(set) var total = 0
  private(set) var questions: [String] = []
  private let searchWeb: any SearchWebUseCase
  private let searchNews: any SearchNewsUseCase
  private let loadQuestions: any LoadQuestionsUseCase

  init(searchWeb: any SearchWebUseCase, searchNews: any SearchNewsUseCase, loadQuestions: any LoadQuestionsUseCase) {
    self.searchWeb = searchWeb
    self.searchNews = searchNews
    self.loadQuestions = loadQuestions
  }

  var pageCount: Int { PageNumbers.count(total: total, size: LiveWebRepository.pageSize) }

  /// The first page of a new search, on the tab that is open.
  func run(_ text: String) async {
    query = text
    page = 1
    await load()
  }

  func select(_ tab: SeekrTab) async {
    guard tab != self.tab else { return }
    self.tab = tab
    page = 1
    await load()
  }

  func goTo(_ number: Int) async {
    guard number >= 1, number <= pageCount, number != page else { return }
    page = number
    await load()
  }

  /// What Try again runs: the page that failed.
  func retry() async { await load() }

  private func load() async {
    guard tab != .images else { return }
    state = .loading
    do {
      switch tab {
      case .all:
        let found = try await searchWeb.execute(query: query, page: page)
        results = found.results
        total = found.total
        if page == 1 { questions = (try? await loadQuestions.execute(query: query)) ?? [] }
      case .news:
        let found = try await searchNews.execute(query: query, page: page)
        results = found.results
        total = found.total
      case .images:
        break
      }
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }
}
