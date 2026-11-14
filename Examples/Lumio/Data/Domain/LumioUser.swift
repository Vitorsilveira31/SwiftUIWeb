/// A person on Lumio.
struct LumioUser: Identifiable, Hashable {
  let id: Int
  let name: String
  let username: String
  let avatarURL: String
  let city: String
  let bio: String
}
