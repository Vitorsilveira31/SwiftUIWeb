import CloneKit

/// The messages from the posts and their users: the sender is the post's user, the subject its title, the body its body.
struct LiveMailboxRepository: MailboxRepository {
  let client: PlaceholderClient

  func messages(scope: MailScope, search: String) async throws -> [MailMessage] {
    async let fetchedPosts = client.mailPosts(filter: scope.filter, search: search)
    async let fetchedUsers = client.users()
    let (posts, users) = try await (fetchedPosts, fetchedUsers)
    // One index per load: scanning every user for each post is quadratic.
    let usersByID = Dictionary(users.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return posts.sorted { $0.id > $1.id }.compactMap { post in
      guard let user = usersByID[post.userId] else { return nil }
      return MailMessage(
        id: post.id,
        sender: MailPerson(name: user.name, address: user.email),
        recipient: post.to,
        subject: post.title,
        body: post.body
      )
    }
  }

  func delete(id: Int) async throws {
    try await client.deletePost(id: id)
  }
}
