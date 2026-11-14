protocol SearchPicturesUseCase: Sendable {
  func execute(query: String, page: Int) async throws -> [SeekrPicture]
}

struct DefaultSearchPicturesUseCase: SearchPicturesUseCase {
  let repository: any PictureRepository

  func execute(query: String, page: Int) async throws -> [SeekrPicture] { try await repository.pictures(query: query, page: page) }
}
