import SwiftUIWeb

/// The jsonplaceholder-shaped API as typed calls. Paths start with `/api`, which the dev server forwards to the mock service
/// (or, with `API=real`, to jsonplaceholder.typicode.com).
public struct PlaceholderClient: Sendable {
  let transport: any PlaceholderTransport

  public init(transport: any PlaceholderTransport = URLSessionTransport()) { self.transport = transport }

  public func users() async throws -> [PlaceholderUser] {
    try JSONDecoder().decode([PlaceholderUser].self, from: await transport.send("GET", "\(PlaceholderImage.base)/users", body: nil))
  }

  public func posts(page: Int, limit: Int) async throws -> [PlaceholderPost] {
    try JSONDecoder().decode([PlaceholderPost].self, from: await transport.send("GET", "\(PlaceholderImage.base)/posts?_page=\(page)&_limit=\(limit)", body: nil))
  }

  public func posts(userId: Int) async throws -> [PlaceholderPost] {
    try JSONDecoder().decode([PlaceholderPost].self, from: await transport.send("GET", "\(PlaceholderImage.base)/users/\(userId)/posts", body: nil))
  }

  public func comments(postId: Int) async throws -> [PlaceholderComment] {
    try JSONDecoder().decode([PlaceholderComment].self, from: await transport.send("GET", "\(PlaceholderImage.base)/posts/\(postId)/comments", body: nil))
  }

  public func albums(userId: Int) async throws -> [PlaceholderAlbum] {
    try JSONDecoder().decode([PlaceholderAlbum].self, from: await transport.send("GET", "\(PlaceholderImage.base)/users/\(userId)/albums", body: nil))
  }

  public func photos(albumId: Int, limit: Int) async throws -> [PlaceholderPhoto] {
    try JSONDecoder().decode([PlaceholderPhoto].self, from: await transport.send("GET", "\(PlaceholderImage.base)/albums/\(albumId)/photos?_limit=\(limit)", body: nil))
  }

  /// A page of photos; `search` (when not empty) matches their titles.
  public func photos(page: Int, limit: Int, search: String) async throws -> [PlaceholderPhoto] {
    let match = search.isEmpty ? "" : "&q=\(PlaceholderQuery.encode(search))"
    return try JSONDecoder().decode(
      [PlaceholderPhoto].self,
      from: await transport.send("GET", "\(PlaceholderImage.base)/photos?_page=\(page)&_limit=\(limit)\(match)", body: nil)
    )
  }

  public func todos(userId: Int) async throws -> [PlaceholderTodo] {
    try JSONDecoder().decode([PlaceholderTodo].self, from: await transport.send("GET", "\(PlaceholderImage.base)/users/\(userId)/todos", body: nil))
  }

  /// Creates a comment. The service answers with it and its new id (the mock keeps it while it runs).
  public func addComment(postId: Int, name: String, email: String, body: String) async throws -> PlaceholderComment {
    let payload = try JSONEncoder().encode(PlaceholderNewComment(postId: postId, name: name, email: email, body: body))
    return try JSONDecoder().decode(PlaceholderComment.self, from: await transport.send("POST", "\(PlaceholderImage.base)/comments", body: payload))
  }
}
