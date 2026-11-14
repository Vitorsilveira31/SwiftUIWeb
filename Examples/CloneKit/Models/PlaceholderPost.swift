/// A post (`/posts`): the text of a feed card, an e-mail, a search result.
public struct PlaceholderPost: Codable, Hashable, Identifiable, Sendable {
  public let id: Int
  public let userId: Int
  public let title: String
  public let body: String
}
