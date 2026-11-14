/// A topic people are talking about, and how many posts are about it.
struct QuillTrend: Identifiable, Hashable, Sendable {
  let id: Int
  let topic: String
  let posts: Int
}
