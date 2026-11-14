import SwiftUIWeb

/// The stays the reader saved: the stays, loaded once, and the ones the session has a heart on. A saved stay opens its page here.
@MainActor @Observable
final class SavedViewModel {
  private(set) var stays: [Stay] = []
  private(set) var state: LoadState = .loading
  private(set) var detail: DetailViewModel?
  private let dependencies: StaylyDependencies
  private let session: StaySession

  init(dependencies: StaylyDependencies, session: StaySession) {
    self.dependencies = dependencies
    self.session = session
  }

  /// The saved stays, in the order of the list. Removing a heart takes the stay off at once.
  var saved: [Stay] { stays.filter { session.isFavorite($0) } }

  func load() async {
    state = .loading
    do {
      stays = try await dependencies.loadStays.execute()
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  /// A saved stay opens with the search every reader starts from: two nights from today.
  func open(_ stay: Stay) {
    detail = DetailViewModel(stay: stay, query: StaySearch.starting(on: Date()), loadDetail: dependencies.loadDetail, reserve: dependencies.reserve, session: session)
  }

  func closeDetail() { detail = nil }
}
