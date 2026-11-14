import SwiftUIWeb

/// A message open in the reading pane: its thread (the post's comments) and the reply being written.
@MainActor @Observable
final class ReadingViewModel {
  let message: MailMessage
  private(set) var replies: [MailReply] = []
  private(set) var state: LoadState = .loading
  private(set) var replyFailed = false
  private(set) var isSending = false
  var draft = ""
  private let load: any LoadRepliesUseCase
  private let reply: any ReplyUseCase

  init(message: MailMessage, load: any LoadRepliesUseCase, reply: any ReplyUseCase) {
    self.message = message
    self.load = load
    self.reply = reply
  }

  /// A reply with nothing but spaces is not worth sending.
  var canSend: Bool { draft.contains(where: { $0 != " " && $0 != "\n" }) }

  func loadReplies() async {
    state = .loading
    do {
      replies = try await load.execute(messageID: message.id)
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  func send() async {
    // A second tap while the reply is on its way does nothing.
    guard canSend, !isSending else { return }
    isSending = true
    defer { isSending = false }
    replyFailed = false
    do {
      replies.append(try await reply.execute(messageID: message.id, text: draft))
      draft = ""
    } catch {
      replyFailed = true
    }
  }
}
