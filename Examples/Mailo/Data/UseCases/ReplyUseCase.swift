protocol ReplyUseCase: Sendable {
  func execute(messageID: Int, text: String) async throws -> MailReply
}

struct DefaultReplyUseCase: ReplyUseCase {
  let repository: any MessageRepository

  func execute(messageID: Int, text: String) async throws -> MailReply { try await repository.reply(messageID: messageID, text: text) }
}
