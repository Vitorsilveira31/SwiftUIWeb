/// A comment under a post: who wrote it and what they said.
struct NeighborlyComment: Identifiable, Hashable {
  let id: Int
  let author: String
  let text: String
}
