protocol LoadStoriesUseCase: Sendable {
  func execute() async throws -> [LumioUser]
}

struct DefaultLoadStoriesUseCase: LoadStoriesUseCase {
  let repository: any FeedRepository

  func execute() async throws -> [LumioUser] { try await repository.people() }
}
