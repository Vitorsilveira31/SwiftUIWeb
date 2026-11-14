protocol LoadMessagesUseCase: Sendable {
  func execute(scope: MailScope, search: String) async throws -> [MailMessage]
}

struct DefaultLoadMessagesUseCase: LoadMessagesUseCase {
  let repository: any MailboxRepository

  func execute(scope: MailScope, search: String) async throws -> [MailMessage] { try await repository.messages(scope: scope, search: search) }
}
