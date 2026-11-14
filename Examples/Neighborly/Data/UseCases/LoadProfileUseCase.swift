protocol LoadProfileUseCase: Sendable {
  func execute(userID: Int) async throws -> NeighborlyProfile
}

struct DefaultLoadProfileUseCase: LoadProfileUseCase {
  let repository: any ProfileRepository

  func execute(userID: Int) async throws -> NeighborlyProfile { try await repository.profile(userID: userID) }
}
