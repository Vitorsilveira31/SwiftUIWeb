import CloneKit

/// Albums and pictures from the API. An album's cover is a wide picture drawn for its id; an album's pictures come in one page.
struct LivePhotosRepository: PhotosRepository {
  let client: PlaceholderClient
  static let pageSize = 24

  func albums(userID: Int) async throws -> [NeighborlyAlbum] {
    try await client.albums(userId: userID).map {
      NeighborlyAlbum(id: $0.id, title: $0.title, coverURL: PlaceholderImage.cover($0.id, width: 900, height: 420))
    }
  }

  func photos(albumID: Int) async throws -> [NeighborlyPhoto] {
    try await client.photos(albumId: albumID, limit: LivePhotosRepository.pageSize).map {
      NeighborlyPhoto(
        id: $0.id,
        title: $0.title,
        thumbnailURL: PlaceholderImage.thumbnail($0.id),
        imageURL: PlaceholderImage.photo($0.id, width: 1000, height: 1000)
      )
    }
  }
}
