protocol LoadAlbumsUseCase: Sendable {
  func execute(userID: Int) async throws -> [NeighborlyAlbum]
}

struct DefaultLoadAlbumsUseCase: LoadAlbumsUseCase {
  let repository: any PhotosRepository

  func execute(userID: Int) async throws -> [NeighborlyAlbum] { try await repository.albums(userID: userID) }
}
