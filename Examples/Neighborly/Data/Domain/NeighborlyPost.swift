/// A post in the feed: its author, its words, a picture when it has one, and how many reacted and commented.
struct NeighborlyPost: Identifiable, Hashable {
  let id: Int
  let author: NeighborlyUser
  let text: String
  let imageURL: String?
  let reactions: Int
  let commentCount: Int
}
