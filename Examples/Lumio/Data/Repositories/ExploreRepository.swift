/// Where the pictures of Explore come from.
protocol ExploreRepository: Sendable {
  func tiles(page: Int, search: String) async throws -> [LumioTile]
}
