import CloneKit

/// A user of the API as a neighbor: the picture is the one drawn for the id, and the bio is the company's catch phrase.
extension NeighborlyUser {
  init(placeholder user: PlaceholderUser) {
    self.init(
      id: user.id,
      name: user.name,
      username: user.username,
      avatarURL: PlaceholderImage.avatar(user.id, size: 128),
      city: user.address.city,
      bio: user.company.catchPhrase
    )
  }
}
