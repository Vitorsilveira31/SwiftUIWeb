protocol AddCommentUseCase: Sendable {
  func execute(postID: Int, text: String) async throws -> LumioComment
}

struct DefaultAddCommentUseCase: AddCommentUseCase {
  let repository: any CommentsRepository

  func execute(postID: Int, text: String) async throws -> LumioComment { try await repository.add(postID: postID, text: text) }
}
