import SwiftUIWeb

/// The suggestions under the search box, for the text typed so far. A suggestion that arrives after the text changed is dropped.
@MainActor @Observable
final class SeekrSuggestionsViewModel {
  private(set) var suggestions: [String] = []
  private let load: any LoadSuggestionsUseCase
  private var latest = ""

  init(load: any LoadSuggestionsUseCase) { self.load = load }

  /// Suggestions for `text`. They are optional: a failed request shows none.
  func typed(_ text: String) async {
    latest = text
    guard !text.isEmpty else {
      suggestions = []
      return
    }
    let found = (try? await load.execute(prefix: text)) ?? []
    guard latest == text else { return }
    suggestions = found
  }

  func clear() {
    latest = ""
    suggestions = []
  }
}
