/// A short post by someone, with the counts under it.
struct QuillPost: Identifiable, Hashable, Sendable {
  let id: Int
  let author: QuillUser
  let text: String
  let likes: Int
  let reposts: Int
  let replies: Int

  /// The post with more replies under it.
  func addingReplies(_ count: Int) -> QuillPost {
    QuillPost(id: id, author: author, text: text, likes: likes, reposts: reposts, replies: replies + count)
  }
}
