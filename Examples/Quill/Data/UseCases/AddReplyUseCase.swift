protocol AddReplyUseCase: Sendable {
  func execute(postID: Int, text: String) async throws -> QuillReply
}

struct DefaultAddReplyUseCase: AddReplyUseCase {
  let repository: any RepliesRepository

  func execute(postID: Int, text: String) async throws -> QuillReply { try await repository.add(postID: postID, text: text) }
}
