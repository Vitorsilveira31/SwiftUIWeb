import CloneKit

/// Posts from the API, each paired with its author by `userId`. The Following feed is the posts of users 1, 2 and 3, newest first.
struct LiveTimelineRepository: TimelineRepository {
  let client: PlaceholderClient
  let currentUserID: Int
  static let pageSize = 10
  static let followedUserIDs = [1, 2, 3]

  func posts(feed: QuillFeed, page: Int) async throws -> [QuillPost] {
    let authors = try await authorsByID()
    let fetched: [PlaceholderPost]
    switch feed {
    case .forYou:
      fetched = try await client.posts(page: page, limit: LiveTimelineRepository.pageSize)
    case .following:
      guard page == 1 else { return [] }
      var all: [PlaceholderPost] = []
      for userID in LiveTimelineRepository.followedUserIDs {
        all += try await client.posts(userId: userID)
      }
      fetched = all.sorted { $0.id > $1.id }
    }
    return fetched.compactMap { post in
      guard let author = authors[post.userId] else { return nil }
      return QuillMapping.post(post, author: author)
    }
  }

  func publish(text: String) async throws -> QuillPost {
    let authors = try await authorsByID()
    guard let author = authors[currentUserID] else { throw PlaceholderError.status(404) }
    let created = try await client.createPost(userId: currentUserID, title: String(text.prefix(40)), body: text)
    // A post written now has no reactions yet; the counts of the others are derived from their ids.
    return QuillPost(id: created.id, author: author, text: text, likes: 0, reposts: 0, replies: 0)
  }

  private func authorsByID() async throws -> [Int: QuillUser] {
    var authors: [Int: QuillUser] = [:]
    for user in try await client.users() {
      authors[user.id] = QuillMapping.user(user)
    }
    return authors
  }
}
