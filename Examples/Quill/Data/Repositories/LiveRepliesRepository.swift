import CloneKit

/// Replies from the API. A new one is written as the reader (a made-up address: the service keeps nothing about who is asking).
struct LiveRepliesRepository: RepliesRepository {
  let client: PlaceholderClient

  func replies(postID: Int) async throws -> [QuillReply] {
    try await client.comments(postId: postID).map(QuillMapping.reply)
  }

  func add(postID: Int, text: String) async throws -> QuillReply {
    let created = try await client.addComment(postId: postID, name: "You", email: "you@quill.test", body: text)
    return QuillMapping.reply(created)
  }
}
