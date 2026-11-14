/// Where the messages of the service come from, and where a message goes when it is deleted for good.
protocol MailboxRepository: Sendable {
  /// The messages of `scope` that match `search`, newest first.
  func messages(scope: MailScope, search: String) async throws -> [MailMessage]
  func delete(id: Int) async throws
}
