/// The person who hosts a stay.
struct StayHost: Identifiable, Hashable {
  let id: Int
  let name: String
  let avatarURL: String
  let city: String
  let bio: String
}
