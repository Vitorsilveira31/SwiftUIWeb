import CloneKit

/// What Mailo needs from the outside, in one place: a test builds it with doubles, the app with `live`.
struct MailoDependencies {
  let loadMessages: any LoadMessagesUseCase
  let deleteMessage: any DeleteMessageUseCase
  let loadReplies: any LoadRepliesUseCase
  let reply: any ReplyUseCase
  let send: any SendMessageUseCase

  static var live: MailoDependencies {
    let client = PlaceholderClient()
    let mailbox = LiveMailboxRepository(client: client)
    let messages = LiveMessageRepository(client: client)
    return MailoDependencies(
      loadMessages: DefaultLoadMessagesUseCase(repository: mailbox),
      deleteMessage: DefaultDeleteMessageUseCase(repository: mailbox),
      loadReplies: DefaultLoadRepliesUseCase(repository: messages),
      reply: DefaultReplyUseCase(repository: messages),
      send: DefaultSendMessageUseCase(repository: messages)
    )
  }
}
