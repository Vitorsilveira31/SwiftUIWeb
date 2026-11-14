import CloneKit

/// Suggestions are the titles of the posts that begin the way the reader has typed, without repeats, at most five.
struct LiveSuggestionRepository: SuggestionRepository {
  let client: PlaceholderClient
  static let limit = 5

  func suggestions(prefix: String) async throws -> [String] {
    let typed = prefix.lowercased()
    guard !typed.isEmpty else { return [] }
    let posts = try await client.searchPosts(query: prefix, page: 1, limit: 30)
    var titles: [String] = []
    for post in posts where post.title.lowercased().hasPrefix(typed) && !titles.contains(post.title) {
      titles.append(post.title)
      if titles.count == LiveSuggestionRepository.limit { break }
    }
    return titles
  }
}
