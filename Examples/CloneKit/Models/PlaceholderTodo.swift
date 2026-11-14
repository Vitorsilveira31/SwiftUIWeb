/// A to-do (`/todos`).
public struct PlaceholderTodo: Codable, Hashable, Identifiable, Sendable {
  public let id: Int
  public let userId: Int
  public let title: String
  public let completed: Bool
}
