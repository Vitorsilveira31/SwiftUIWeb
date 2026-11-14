/// A picture with its caption, by someone.
struct LumioPost: Identifiable, Hashable {
  let id: Int
  let author: LumioUser
  let imageURL: String
  let caption: String
  let likes: Int
  let commentCount: Int
}
