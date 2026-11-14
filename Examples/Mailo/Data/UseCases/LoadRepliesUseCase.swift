protocol LoadRepliesUseCase: Sendable {
  func execute(messageID: Int) async throws -> [MailReply]
}

struct DefaultLoadRepliesUseCase: LoadRepliesUseCase {
  let repository: any MessageRepository

  func execute(messageID: Int) async throws -> [MailReply] { try await repository.replies(messageID: messageID) }
}
