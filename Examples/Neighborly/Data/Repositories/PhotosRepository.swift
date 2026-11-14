/// Where a person's albums and an album's pictures come from.
protocol PhotosRepository: Sendable {
  func albums(userID: Int) async throws -> [NeighborlyAlbum]
  func photos(albumID: Int) async throws -> [NeighborlyPhoto]
}
