protocol LoadTrendsUseCase: Sendable {
  func execute() async throws -> [QuillTrend]
}

struct DefaultLoadTrendsUseCase: LoadTrendsUseCase {
  let repository: any SidebarRepository

  func execute() async throws -> [QuillTrend] { try await repository.trends() }
}
