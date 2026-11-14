import CloneKit

/// The feed from the API: posts paired with their authors by `userId`. Every other post has a picture drawn for its id; a new post is text only.
struct LiveFeedRepository: FeedRepository {
  let client: PlaceholderClient
  let currentUserID: Int
  static let pageSize = 6
  static let commentsPerPost = 5

  func posts(page: Int) async throws -> [NeighborlyPost] {
    async let fetchedPosts = client.posts(page: page, limit: LiveFeedRepository.pageSize)
    async let fetchedUsers = client.users()
    let (posts, users) = try await (fetchedPosts, fetchedUsers)
    // One index per load: scanning every user for each post is quadratic.
    let usersByID = Dictionary(users.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return posts.compactMap { post in
      guard let author = usersByID[post.userId] else { return nil }
      return NeighborlyPost(
        id: post.id,
        author: NeighborlyUser(placeholder: author),
        text: post.body,
        imageURL: post.id % 2 == 0 ? PlaceholderImage.photo(post.id, width: 940, height: 940) : nil,
        // Wrapping multiply on the magnitude: ids can be large, and Int is 32 bits in the browser build.
        reactions: Int((post.id.magnitude &* 29) % 180) + 4,
        commentCount: LiveFeedRepository.commentsPerPost
      )
    }
  }

  func publish(text: String) async throws -> NeighborlyPost {
    async let created = client.createPost(userId: currentUserID, title: "", body: text)
    async let author = client.user(id: currentUserID)
    let (post, user) = try await (created, author)
    return NeighborlyPost(id: post.id, author: NeighborlyUser(placeholder: user), text: post.body, imageURL: nil, reactions: 0, commentCount: 0)
  }
}
