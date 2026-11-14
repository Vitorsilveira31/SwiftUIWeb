import CloneKit

/// A thread is the post's comments; the account writes its replies and its messages as itself.
struct LiveMessageRepository: MessageRepository {
  let client: PlaceholderClient

  func replies(messageID: Int) async throws -> [MailReply] {
    try await client.comments(postId: messageID).map { comment in
      MailReply(
        id: comment.id,
        author: MailPerson(name: comment.email.split(separator: "@").first.map(String.init) ?? comment.email, address: comment.email),
        body: comment.body
      )
    }
  }

  func reply(messageID: Int, text: String) async throws -> MailReply {
    let me = MailoAccount.person
    let created = try await client.addComment(postId: messageID, name: me.name, email: me.address, body: text)
    return MailReply(id: created.id, author: me, body: text)
  }

  func send(to: String, subject: String, body: String) async throws -> MailMessage {
    let created = try await client.sendPost(userId: MailoAccount.userID, to: to, title: subject, body: body)
    return MailMessage(id: created.id, sender: MailoAccount.person, recipient: to, subject: subject, body: body)
  }
}
