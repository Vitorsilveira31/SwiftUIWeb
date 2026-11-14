protocol LoadProfileUseCase: Sendable {
  func execute(userID: Int) async throws -> LumioProfile
}

struct DefaultLoadProfileUseCase: LoadProfileUseCase {
  let repository: any ProfileRepository

  func execute(userID: Int) async throws -> LumioProfile { try await repository.profile(userID: userID) }
}
