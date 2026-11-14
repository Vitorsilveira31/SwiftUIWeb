/// A comment (`/comments`, `/posts/:id/comments`).
public struct PlaceholderComment: Codable, Hashable, Identifiable, Sendable {
  public let id: Int
  public let postId: Int
  public let name: String
  public let email: String
  public let body: String

  public init(id: Int, postId: Int, name: String, email: String, body: String) {
    self.id = id
    self.postId = postId
    self.name = name
    self.email = email
    self.body = body
  }
}

/// What is sent to create a comment: the service answers with the comment and its new id.
struct PlaceholderNewComment: Codable {
  let postId: Int
  let name: String
  let email: String
  let body: String
}
