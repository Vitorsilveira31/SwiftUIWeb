import CloneKit

/// A profile from the API: the person with their cover, the posts and albums counted, and friends: the first few other people on the service.
struct LiveProfileRepository: ProfileRepository {
  let client: PlaceholderClient
  static let friendCount = 6

  func profile(userID: Int) async throws -> NeighborlyProfile {
    async let person = client.user(id: userID)
    async let posts = client.posts(userId: userID)
    async let albums = client.albums(userId: userID)
    async let everyone = client.users()
    let (found, userPosts, userAlbums, people) = try await (person, posts, albums, everyone)
    let friends = people.filter { $0.id != userID }.prefix(LiveProfileRepository.friendCount)
    return NeighborlyProfile(
      user: NeighborlyUser(placeholder: found),
      coverURL: PlaceholderImage.cover(userID),
      postCount: userPosts.count,
      albumCount: userAlbums.count,
      friends: friends.map { NeighborlyUser(placeholder: $0) }
    )
  }
}
