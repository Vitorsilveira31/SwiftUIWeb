protocol LoadCommentsUseCase: Sendable {
  func execute(postID: Int) async throws -> [NeighborlyComment]
}

struct DefaultLoadCommentsUseCase: LoadCommentsUseCase {
  let repository: any CommentsRepository

  func execute(postID: Int) async throws -> [NeighborlyComment] { try await repository.comments(postID: postID) }
}
