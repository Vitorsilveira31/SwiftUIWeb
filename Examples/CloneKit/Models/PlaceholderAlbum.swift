/// An album (`/albums`): a titled set of photos that belongs to a user.
public struct PlaceholderAlbum: Codable, Hashable, Identifiable, Sendable {
  public let id: Int
  public let userId: Int
  public let title: String
}
