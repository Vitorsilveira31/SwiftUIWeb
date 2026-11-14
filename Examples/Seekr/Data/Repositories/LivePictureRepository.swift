import CloneKit

/// The pictures of a search: the API's photos whose titles match the query, a page at a time.
struct LivePictureRepository: PictureRepository {
  let client: PlaceholderClient
  static let pageSize = 30

  func pictures(query: String, page: Int) async throws -> [SeekrPicture] {
    try await client.photos(page: page, limit: LivePictureRepository.pageSize, search: query).map {
      SeekrPicture(
        id: $0.id,
        title: $0.title,
        thumbnailURL: PlaceholderImage.thumbnail($0.id),
        imageURL: PlaceholderImage.photo($0.id, width: 900, height: 900)
      )
    }
  }
}
