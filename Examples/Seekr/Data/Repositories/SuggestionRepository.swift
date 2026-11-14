/// Where the suggestions of the search box come from.
protocol SuggestionRepository: Sendable {
  func suggestions(prefix: String) async throws -> [String]
}
