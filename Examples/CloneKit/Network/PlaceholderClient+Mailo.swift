import SwiftUIWeb

/// A post as a mail message: the title is the subject, the body the text, and `to` the recipient a sent message was given
/// (the service keeps it when it is sent; the posts it came with have none).
public struct PlaceholderMailPost: Codable, Hashable, Identifiable, Sendable {
  public let id: Int
  public let userId: Int
  public let title: String
  public let body: String
  public let to: String?
}

/// What is sent to write a message: the service answers with the post and its new id.
struct PlaceholderNewMailPost: Codable {
  let userId: Int
  let to: String
  let title: String
  let body: String
}

/// The calls of the mail client: the posts of a filter (`userId_ne=1`, `userId=1`, or none), a message sent and one deleted.
extension PlaceholderClient {
  /// The posts that match `filter` and `search` (the service's `q`), in the order the service keeps them.
  public func mailPosts(filter: String, search: String) async throws -> [PlaceholderMailPost] {
    let parts = [filter, search.isEmpty ? "" : "q=\(PlaceholderQuery.encode(search))"].filter { !$0.isEmpty }
    let query = parts.isEmpty ? "" : "?\(parts.joined(separator: "&"))"
    return try JSONDecoder().decode([PlaceholderMailPost].self, from: await transport.send("GET", "\(PlaceholderImage.base)/posts\(query)", body: nil))
  }

  /// Sends a message: a post by `userId`, to `to`.
  public func sendPost(userId: Int, to: String, title: String, body: String) async throws -> PlaceholderMailPost {
    let payload = try JSONEncoder().encode(PlaceholderNewMailPost(userId: userId, to: to, title: title, body: body))
    return try JSONDecoder().decode(PlaceholderMailPost.self, from: await transport.send("POST", "\(PlaceholderImage.base)/posts", body: payload))
  }

  /// Deletes a message for good (the service answers with nothing).
  public func deletePost(id: Int) async throws {
    _ = try await transport.send("DELETE", "\(PlaceholderImage.base)/posts/\(id)", body: nil)
  }
}
