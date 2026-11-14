protocol LoadStayDetailUseCase: Sendable {
  func execute(stayID: Int) async throws -> StayDetail
}

struct DefaultLoadStayDetailUseCase: LoadStayDetailUseCase {
  let repository: any StaysRepository

  func execute(stayID: Int) async throws -> StayDetail { try await repository.detail(stayID: stayID) }
}
