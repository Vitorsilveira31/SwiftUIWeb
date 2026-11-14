/// The words of the results screen.
enum ResultsStrings {
  static let loading = "Searching…"
  static let failedTitle = "The results could not load"
  static let retry = "Try again"
  static let previous = "Previous"
  static let next = "Next"
  static let peopleAlsoAsk = "People also ask"

  static func title(_ tab: SeekrTab) -> String {
    switch tab {
    case .all: return "All"
    case .images: return "Images"
    case .news: return "News"
    }
  }

  static func count(_ total: Int) -> String { total == 1 ? "About 1 result" : "About \(total) results" }

  static func noResults(_ query: String) -> String { "No results for “\(query)”. Try other words." }
}
