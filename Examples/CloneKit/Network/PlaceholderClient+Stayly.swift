import SwiftUIWeb

/// The calls the Stayly example needs beyond the core client: every album (a stay is one), one post (a stay's description) and a
/// to-do (the record of a reservation).
extension PlaceholderClient {
  public func albums() async throws -> [PlaceholderAlbum] {
    try JSONDecoder().decode([PlaceholderAlbum].self, from: await transport.send("GET", "\(PlaceholderImage.base)/albums", body: nil))
  }

  public func post(id: Int) async throws -> PlaceholderPost {
    try JSONDecoder().decode(PlaceholderPost.self, from: await transport.send("GET", "\(PlaceholderImage.base)/posts/\(id)", body: nil))
  }

  /// Creates a to-do. The service answers with it and its new id (the mock keeps it while it runs).
  public func addTodo(userId: Int, title: String, completed: Bool) async throws -> PlaceholderTodo {
    let payload = try JSONEncoder().encode(PlaceholderNewTodo(userId: userId, title: title, completed: completed))
    return try JSONDecoder().decode(PlaceholderTodo.self, from: await transport.send("POST", "\(PlaceholderImage.base)/todos", body: payload))
  }
}

struct PlaceholderNewTodo: Codable {
  let userId: Int
  let title: String
  let completed: Bool
}
