import SwiftUIWeb

/// The calls Neighborly makes beyond the shared client: one user by id, and a post it publishes.
extension PlaceholderClient {
  /// One user (`/users/:id`).
  public func user(id: Int) async throws -> PlaceholderUser {
    try JSONDecoder().decode(PlaceholderUser.self, from: await transport.send("GET", "\(PlaceholderImage.base)/users/\(id)", body: nil))
  }

  /// Creates a post. The service answers with it and its new id (the mock keeps it while it runs).
  public func createPost(userId: Int, title: String, body: String) async throws -> PlaceholderPost {
    let payload = try JSONEncoder().encode(PlaceholderNewPost(userId: userId, title: title, body: body))
    return try JSONDecoder().decode(PlaceholderPost.self, from: await transport.send("POST", "\(PlaceholderImage.base)/posts", body: payload))
  }
}

/// What is sent to create a post: the service answers with the post and its new id.
struct PlaceholderNewPost: Codable {
  let userId: Int
  let title: String
  let body: String
}
