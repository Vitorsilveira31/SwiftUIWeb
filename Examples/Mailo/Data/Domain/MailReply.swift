/// A reply in a message's thread: a comment on the post.
struct MailReply: Identifiable, Hashable, Sendable {
  let id: Int
  let author: MailPerson
  let body: String
}
