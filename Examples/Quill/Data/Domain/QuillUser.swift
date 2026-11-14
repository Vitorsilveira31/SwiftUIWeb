/// A person on Quill: who they are and how they are called.
struct QuillUser: Identifiable, Hashable, Sendable {
  let id: Int
  let name: String
  let handle: String
  let avatarURL: String
}
