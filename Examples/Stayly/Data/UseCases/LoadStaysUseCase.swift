protocol LoadStaysUseCase: Sendable {
  func execute() async throws -> [Stay]
}

struct DefaultLoadStaysUseCase: LoadStaysUseCase {
  let repository: any StaysRepository

  func execute() async throws -> [Stay] { try await repository.stays() }
}
