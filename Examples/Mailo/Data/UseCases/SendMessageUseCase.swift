protocol SendMessageUseCase: Sendable {
  func execute(to: String, subject: String, body: String) async throws -> MailMessage
}

struct DefaultSendMessageUseCase: SendMessageUseCase {
  let repository: any MessageRepository

  func execute(to: String, subject: String, body: String) async throws -> MailMessage {
    try await repository.send(to: to, subject: subject, body: body)
  }
}
