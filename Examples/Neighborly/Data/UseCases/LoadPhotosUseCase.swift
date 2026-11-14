protocol LoadPhotosUseCase: Sendable {
  func execute(albumID: Int) async throws -> [NeighborlyPhoto]
}

struct DefaultLoadPhotosUseCase: LoadPhotosUseCase {
  let repository: any PhotosRepository

  func execute(albumID: Int) async throws -> [NeighborlyPhoto] { try await repository.photos(albumID: albumID) }
}
