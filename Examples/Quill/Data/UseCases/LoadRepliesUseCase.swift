protocol LoadRepliesUseCase: Sendable {
  func execute(postID: Int) async throws -> [QuillReply]
}

struct DefaultLoadRepliesUseCase: LoadRepliesUseCase {
  let repository: any RepliesRepository

  func execute(postID: Int) async throws -> [QuillReply] { try await repository.replies(postID: postID) }
}
