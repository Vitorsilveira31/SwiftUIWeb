/// Where a post's comments are read and written.
protocol CommentsRepository: Sendable {
  func comments(postID: Int) async throws -> [NeighborlyComment]
  func add(postID: Int, text: String) async throws -> NeighborlyComment
}
