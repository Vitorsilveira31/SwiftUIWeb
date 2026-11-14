import SwiftUIWeb

/// The search box's text, the screen, and the recent searches. A submitted search runs the results and the pictures.
@MainActor @Observable
final class SeekrShellViewModel {
  static let recentLimit = 6
  var query = ""
  private(set) var route = SeekrRoute.home
  private(set) var recent: [String] = []
  let results: SeekrResultsViewModel
  let images: SeekrImagesViewModel
  let suggestions: SeekrSuggestionsViewModel

  init(results: SeekrResultsViewModel, images: SeekrImagesViewModel, suggestions: SeekrSuggestionsViewModel) {
    self.results = results
    self.images = images
    self.suggestions = suggestions
  }

  /// Searches for `text`: the results screen opens on it, the text joins the recent searches, and the pictures are searched too.
  func submit(_ text: String) async {
    guard !text.isEmpty else { return }
    query = text
    remember(text)
    suggestions.clear()
    route = .results
    await results.run(text)
    await images.run(text)
  }

  /// The search box changed: its text is kept, and the suggestions follow it.
  func edit(_ text: String) {
    query = text
    Task { await suggestions.typed(text) }
  }

  func goHome() {
    route = .home
    suggestions.clear()
  }

  private func remember(_ text: String) {
    recent.removeAll { $0 == text }
    recent.insert(text, at: 0)
    if recent.count > SeekrShellViewModel.recentLimit { recent.removeLast(recent.count - SeekrShellViewModel.recentLimit) }
  }
}
