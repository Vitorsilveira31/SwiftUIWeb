/// Where the replies under a post come from.
protocol RepliesRepository: Sendable {
  func replies(postID: Int) async throws -> [QuillReply]
  func add(postID: Int, text: String) async throws -> QuillReply
}
