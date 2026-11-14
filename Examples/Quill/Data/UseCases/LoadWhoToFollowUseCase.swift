protocol LoadWhoToFollowUseCase: Sendable {
  func execute() async throws -> [QuillUser]
}

struct DefaultLoadWhoToFollowUseCase: LoadWhoToFollowUseCase {
  let repository: any SidebarRepository

  func execute() async throws -> [QuillUser] { try await repository.suggestions() }
}
