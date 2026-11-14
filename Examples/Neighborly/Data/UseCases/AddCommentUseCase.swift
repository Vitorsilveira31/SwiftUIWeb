protocol AddCommentUseCase: Sendable {
  func execute(postID: Int, text: String) async throws -> NeighborlyComment
}

struct DefaultAddCommentUseCase: AddCommentUseCase {
  let repository: any CommentsRepository

  func execute(postID: Int, text: String) async throws -> NeighborlyComment { try await repository.add(postID: postID, text: text) }
}
