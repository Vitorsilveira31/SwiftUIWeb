protocol DeleteMessageUseCase: Sendable {
  func execute(id: Int) async throws
}

struct DefaultDeleteMessageUseCase: DeleteMessageUseCase {
  let repository: any MailboxRepository

  func execute(id: Int) async throws { try await repository.delete(id: id) }
}
