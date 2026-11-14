/// The address of the first result of a search, for "I am feeling lucky"; nil when the search has none.
protocol FeelingLuckyUseCase: Sendable {
  func execute(query: String) async throws -> String?
}

struct DefaultFeelingLuckyUseCase: FeelingLuckyUseCase {
  let repository: any WebRepository

  func execute(query: String) async throws -> String? {
    try await repository.results(query: query, page: 1).results.first { !$0.link.isEmpty }?.link
  }
}
