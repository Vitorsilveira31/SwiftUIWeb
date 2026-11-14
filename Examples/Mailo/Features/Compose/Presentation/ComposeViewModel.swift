import SwiftUIWeb

/// The new message: its recipient, subject and body. A draft opened here is the one it was saved as.
@MainActor @Observable
final class ComposeViewModel {
  var to = ""
  var subject = ""
  var body = ""
  private(set) var failed = false
  private(set) var isSending = false
  private var draftID: Int?
  private let memory: MailboxState
  private let sender: any SendMessageUseCase

  init(draft: MailMessage?, memory: MailboxState, sender: any SendMessageUseCase) {
    self.memory = memory
    self.sender = sender
    if let draft {
      to = draft.recipient ?? ""
      subject = draft.subject
      body = draft.body
      draftID = draft.id
    }
  }

  /// A recipient is an address: it has an "@" in it.
  var canSend: Bool { to.contains("@") }

  func saveDraft() {
    draftID = memory.saveDraft(id: draftID, to: to, subject: subject, body: body)
  }

  /// Sends the message; a draft it came from is gone then. Returns whether it was sent.
  func send() async -> Bool {
    // A second tap while the message is on its way does nothing.
    guard canSend, !isSending else { return false }
    isSending = true
    defer { isSending = false }
    failed = false
    do {
      _ = try await sender.execute(to: to, subject: subject, body: body)
    } catch {
      failed = true
      return false
    }
    if let draftID { memory.removeDrafts([draftID]) }
    return true
  }
}
