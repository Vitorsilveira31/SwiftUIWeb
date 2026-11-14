import SwiftUIWeb

/// The app's state and the actions that cross features: the mailbox, the message open in the reading pane, and the compose sheet.
@MainActor @Observable
final class MailoController {
  let mailbox: MailboxViewModel
  private(set) var reader: ReadingViewModel?
  /// The compose sheet is shown while this is set.
  private(set) var compose: ComposeViewModel?
  private let dependencies: MailoDependencies

  init(dependencies: MailoDependencies) {
    self.dependencies = dependencies
    mailbox = MailboxViewModel(list: dependencies.loadMessages, remove: dependencies.deleteMessage, memory: MailboxState())
  }

  func start() async { await mailbox.load() }

  func select(_ folder: MailFolder) async {
    reader = nil
    await mailbox.select(folder)
  }

  /// Opens a message in the reading pane and reads it; a draft opens in the compose sheet instead.
  func open(_ message: MailMessage) {
    if message.isDraft {
      startCompose(editing: message)
      return
    }
    mailbox.markOpened(message.id)
    let thread = ReadingViewModel(message: message, load: dependencies.loadReplies, reply: dependencies.reply)
    reader = thread
    Task { await thread.loadReplies() }
  }

  func closeReader() { reader = nil }

  /// Deletes messages; the message in the reading pane closes when it is among them.
  func delete(_ ids: Set<Int>) async {
    if let open = reader?.message.id, ids.contains(open) { reader = nil }
    await mailbox.delete(ids)
  }

  func startCompose(editing draft: MailMessage? = nil) {
    compose = ComposeViewModel(draft: draft, memory: mailbox.memory, sender: dependencies.send)
  }

  /// Closes the compose sheet and lists the mail again, since a message may have been sent or a draft saved.
  func closeCompose() {
    compose = nil
    Task { await mailbox.load() }
  }
}
