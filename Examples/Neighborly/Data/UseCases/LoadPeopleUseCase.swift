protocol LoadPeopleUseCase: Sendable {
  func execute() async throws -> [NeighborlyUser]
}

struct DefaultLoadPeopleUseCase: LoadPeopleUseCase {
  let repository: any PeopleRepository

  func execute() async throws -> [NeighborlyUser] { try await repository.people() }
}
