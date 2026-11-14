protocol LoadExploreUseCase: Sendable {
  func execute(page: Int, search: String) async throws -> [LumioTile]
}

struct DefaultLoadExploreUseCase: LoadExploreUseCase {
  let repository: any ExploreRepository

  func execute(page: Int, search: String) async throws -> [LumioTile] { try await repository.tiles(page: page, search: search) }
}
