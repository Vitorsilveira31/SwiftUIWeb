/// Where a message's thread is read and written, and where a new message is sent.
protocol MessageRepository: Sendable {
  func replies(messageID: Int) async throws -> [MailReply]
  func reply(messageID: Int, text: String) async throws -> MailReply
  func send(to: String, subject: String, body: String) async throws -> MailMessage
}
