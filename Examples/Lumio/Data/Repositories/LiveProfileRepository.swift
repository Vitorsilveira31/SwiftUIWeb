import CloneKit

/// A profile from the API: the user, their posts counted, their albums as highlights and the first album's pictures as the grid.
struct LiveProfileRepository: ProfileRepository {
  let client: PlaceholderClient

  func profile(userID: Int) async throws -> LumioProfile {
    async let users = client.users()
    async let posts = client.posts(userId: userID)
    async let albums = client.albums(userId: userID)
    let (allUsers, userPosts, userAlbums) = try await (users, posts, albums)
    guard let found = allUsers.first(where: { $0.id == userID }) else { throw PlaceholderError.status(404) }
    var photos: [PlaceholderPhoto] = []
    if let first = userAlbums.first { photos = try await client.photos(albumId: first.id, limit: 18) }
    return LumioProfile(
      user: LumioUser(id: found.id, name: found.name, username: found.username, avatarURL: PlaceholderImage.avatar(found.id, size: 256), city: found.address.city, bio: found.company.catchPhrase),
      postCount: userPosts.count,
      albumTitles: userAlbums.map(\.title),
      tiles: photos.map { LumioTile(id: $0.id, imageURL: PlaceholderImage.photo($0.id, width: 400, height: 400), title: $0.title) }
    )
  }
}
