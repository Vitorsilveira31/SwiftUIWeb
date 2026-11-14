protocol LoadCommentsUseCase: Sendable {
  func execute(postID: Int) async throws -> [LumioComment]
}

struct DefaultLoadCommentsUseCase: LoadCommentsUseCase {
  let repository: any CommentsRepository

  func execute(postID: Int) async throws -> [LumioComment] { try await repository.comments(postID: postID) }
}
