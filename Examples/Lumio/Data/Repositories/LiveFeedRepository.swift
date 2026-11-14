import CloneKit

/// The feed from the jsonplaceholder-shaped API: posts and users, paired by `userId`; each post's picture is the one drawn for its id.
struct LiveFeedRepository: FeedRepository {
  let client: PlaceholderClient
  static let pageSize = 6

  func posts(page: Int) async throws -> [LumioPost] {
    async let fetchedPosts = client.posts(page: page, limit: LiveFeedRepository.pageSize)
    async let fetchedUsers = people()
    let (posts, users) = try await (fetchedPosts, fetchedUsers)
    // One index per load: scanning every user for each post is quadratic.
    let usersByID = Dictionary(users.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return posts.compactMap { post in
      guard let author = usersByID[post.userId] else { return nil }
      return LumioPost(
        id: post.id,
        author: author,
        imageURL: PlaceholderImage.photo(post.id, width: 940, height: 940),
        caption: "\(post.title)\n\(post.body)",
        // Wrapping multiply on the magnitude: ids can be large, and Int is 32 bits in the browser build.
        likes: Int((post.id.magnitude &* 37) % 2_500) + 12,
        commentCount: 5
      )
    }
  }

  func people() async throws -> [LumioUser] {
    try await client.users().map { LumioUser(id: $0.id, name: $0.name, username: $0.username, avatarURL: PlaceholderImage.avatar($0.id, size: 128), city: $0.address.city, bio: $0.company.catchPhrase) }
  }
}
