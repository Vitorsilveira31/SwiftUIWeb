/// A reply under a post: who wrote it and what they said.
struct QuillReply: Identifiable, Hashable, Sendable {
  let id: Int
  let name: String
  let text: String
  let avatarURL: String
}
