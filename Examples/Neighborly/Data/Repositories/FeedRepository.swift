/// Where the feed comes from, and where a new post goes.
protocol FeedRepository: Sendable {
  func posts(page: Int) async throws -> [NeighborlyPost]
  func publish(text: String) async throws -> NeighborlyPost
}
