/// A neighbor: a person on Neighborly, with the city they live in and what they do.
struct NeighborlyUser: Identifiable, Hashable {
  let id: Int
  let name: String
  let username: String
  let avatarURL: String
  let city: String
  let bio: String
}
