/// A comment under a post.
struct LumioComment: Identifiable, Hashable {
  let id: Int
  let author: String
  let text: String
}
