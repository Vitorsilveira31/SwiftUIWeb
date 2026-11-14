protocol LoadQuestionsUseCase: Sendable {
  func execute(query: String) async throws -> [String]
}

struct DefaultLoadQuestionsUseCase: LoadQuestionsUseCase {
  let repository: any WebRepository

  func execute(query: String) async throws -> [String] { try await repository.questions(query: query) }
}
