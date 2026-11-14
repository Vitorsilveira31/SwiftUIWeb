import CloneKit

/// Comments from the API; a new one is posted as the reader (a made-up address, the service keeps nothing about who is asking).
struct LiveCommentsRepository: CommentsRepository {
  let client: PlaceholderClient

  func comments(postID: Int) async throws -> [LumioComment] {
    try await client.comments(postId: postID).map { LumioComment(id: $0.id, author: $0.email.split(separator: "@").first.map(String.init) ?? $0.email, text: $0.body) }
  }

  func add(postID: Int, text: String) async throws -> LumioComment {
    let created = try await client.addComment(postId: postID, name: "You", email: "you@lumio.test", body: text)
    return LumioComment(id: created.id, author: "you", text: text)
  }
}
