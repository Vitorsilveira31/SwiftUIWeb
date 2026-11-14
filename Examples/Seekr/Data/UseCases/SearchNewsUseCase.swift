protocol SearchNewsUseCase: Sendable {
  func execute(query: String, page: Int) async throws -> SeekrResultPage
}

struct DefaultSearchNewsUseCase: SearchNewsUseCase {
  let repository: any WebRepository

  func execute(query: String, page: Int) async throws -> SeekrResultPage { try await repository.news(query: query, page: page) }
}
