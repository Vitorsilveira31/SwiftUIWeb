protocol LoadSuggestionsUseCase: Sendable {
  func execute(prefix: String) async throws -> [String]
}

struct DefaultLoadSuggestionsUseCase: LoadSuggestionsUseCase {
  let repository: any SuggestionRepository

  func execute(prefix: String) async throws -> [String] { try await repository.suggestions(prefix: prefix) }
}
