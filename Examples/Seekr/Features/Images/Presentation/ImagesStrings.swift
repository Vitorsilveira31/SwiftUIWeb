/// The words of the Images tab.
enum ImagesStrings {
  static let loading = "Loading pictures…"
  static let failedTitle = "The pictures could not load"
  static let retry = "Try again"
  static let more = "Show more pictures"
  static let close = "Close preview"

  static func noPictures(_ query: String) -> String { "No pictures for “\(query)”. Try other words." }

  static func number(_ id: Int) -> String { "Picture \(id)" }
}
