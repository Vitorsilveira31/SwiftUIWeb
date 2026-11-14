/// A photo (`/photos`). `url` and `thumbnailUrl` are paths the mock API draws; read them through `PlaceholderImage`.
public struct PlaceholderPhoto: Codable, Hashable, Identifiable, Sendable {
  public let id: Int
  public let albumId: Int
  public let title: String
  public let url: String
  public let thumbnailUrl: String
}
