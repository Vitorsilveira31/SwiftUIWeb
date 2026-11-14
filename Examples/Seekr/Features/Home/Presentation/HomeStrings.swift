/// The words of the home page.
enum HomeStrings {
  static let tagline = "Search the posts, pictures and people of the web."
  static let lucky = "I am feeling lucky"
  static let recent = "Recent searches"

  static func noLuckyResult(_ query: String) -> String { "No results for “\(query)”, so there is no first result to open." }
}
