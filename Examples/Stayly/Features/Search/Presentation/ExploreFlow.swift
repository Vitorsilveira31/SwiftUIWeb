import SwiftUIWeb

/// The Explore tab's way through a search: the form, the results of the search it made, and one stay's page. The root owns it, so the
/// form keeps what was typed while the reader moves between the screens.
@MainActor @Observable
final class ExploreFlow {
  private(set) var route = ExploreRoute.form
  let search: SearchViewModel
  private(set) var results: ResultsViewModel?
  private(set) var detail: DetailViewModel?
  private let dependencies: StaylyDependencies
  private let session: StaySession

  init(dependencies: StaylyDependencies, session: StaySession) {
    self.dependencies = dependencies
    self.session = session
    search = SearchViewModel(load: dependencies.loadStays, today: Date())
  }

  func showResults() {
    results = ResultsViewModel(query: search.stayQuery, load: dependencies.loadStays)
    route = .results
  }

  func openStay(_ stay: Stay) {
    guard let results else { return }
    detail = DetailViewModel(stay: stay, query: results.query, loadDetail: dependencies.loadDetail, reserve: dependencies.reserve, session: session)
    route = .stay
  }

  func backToResults() { route = .results }

  func backToForm() { route = .form }
}
