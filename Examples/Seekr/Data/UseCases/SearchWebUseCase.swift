protocol SearchWebUseCase: Sendable {
  func execute(query: String, page: Int) async throws -> SeekrResultPage
}

struct DefaultSearchWebUseCase: SearchWebUseCase {
  let repository: any WebRepository

  func execute(query: String, page: Int) async throws -> SeekrResultPage { try await repository.results(query: query, page: page) }
}
