/// A person's profile: who they are, the wide picture on top of it, how much they have, and their friends.
struct NeighborlyProfile {
  let user: NeighborlyUser
  let coverURL: String
  let postCount: Int
  let albumCount: Int
  let friends: [NeighborlyUser]
}
