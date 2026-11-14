import CloneKit

/// Comments from the API. The service keeps an address, not a user id, so a commenter is the user who has that address; a new comment is written as the reader.
struct LiveCommentsRepository: CommentsRepository {
  let client: PlaceholderClient
  let currentUserID: Int

  func comments(postID: Int) async throws -> [NeighborlyComment] {
    async let fetchedComments = client.comments(postId: postID)
    async let fetchedUsers = client.users()
    let (comments, users) = try await (fetchedComments, fetchedUsers)
    // One index per load: scanning every user for each comment is quadratic.
    let namesByEmail = Dictionary(users.map { ($0.email, $0.name) }, uniquingKeysWith: { first, _ in first })
    return comments.map { comment in
      let author = namesByEmail[comment.email] ?? comment.email
      return NeighborlyComment(id: comment.id, author: author, text: comment.body)
    }
  }

  func add(postID: Int, text: String) async throws -> NeighborlyComment {
    let reader = try await client.user(id: currentUserID)
    let created = try await client.addComment(postId: postID, name: reader.name, email: reader.email, body: text)
    return NeighborlyComment(id: created.id, author: reader.name, text: text)
  }
}
