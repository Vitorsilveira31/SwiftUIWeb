import CloneKit

/// Explore from the API's photos, a page at a time, filtered by the search when there is one.
struct LiveExploreRepository: ExploreRepository {
  let client: PlaceholderClient
  static let pageSize = 30

  func tiles(page: Int, search: String) async throws -> [LumioTile] {
    try await client.photos(page: page, limit: LiveExploreRepository.pageSize, search: search).map {
      LumioTile(id: $0.id, imageURL: PlaceholderImage.photo($0.id, width: 400, height: 400), title: $0.title)
    }
  }
}
