protocol LoadFeedUseCase: Sendable {
  func execute(page: Int) async throws -> [LumioPost]
}

struct DefaultLoadFeedUseCase: LoadFeedUseCase {
  let repository: any FeedRepository

  func execute(page: Int) async throws -> [LumioPost] { try await repository.posts(page: page) }
}
