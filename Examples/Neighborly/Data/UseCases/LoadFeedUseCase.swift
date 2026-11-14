protocol LoadFeedUseCase: Sendable {
  func execute(page: Int) async throws -> [NeighborlyPost]
}

struct DefaultLoadFeedUseCase: LoadFeedUseCase {
  let repository: any FeedRepository

  func execute(page: Int) async throws -> [NeighborlyPost] { try await repository.posts(page: page) }
}
