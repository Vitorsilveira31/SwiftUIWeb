import SwiftUIWeb

/// Select all, then either the folder's name or the actions for the selection (mark read or unread, delete), and the pages on the right.
struct MailboxToolbar: View {
  let app: MailoController

  var body: some View {
    let mailbox = app.mailbox
    HStack(spacing: 12) {
      Toggle(isOn: Binding(get: { mailbox.allOnPageSelected }, set: { _ in mailbox.toggleSelectAll() })) {
        Text(MailboxStrings.selectAll)
      }
      .toggleStyle(.checkbox)
      if mailbox.selected.isEmpty {
        Text(MailboxStrings.title(mailbox.folder)).fontWeight(Font.Weight.bold)
      } else {
        Text(MailboxStrings.selected(mailbox.selected.count))
        Button(MailboxStrings.markRead) { mailbox.markSelected(unread: false) }.buttonStyle(.bordered)
        Button(MailboxStrings.markUnread) { mailbox.markSelected(unread: true) }.buttonStyle(.bordered)
        Button(MailboxStrings.delete) { Task { await app.delete(mailbox.selected) } }.buttonStyle(.bordered)
      }
      Spacer()
      if !mailbox.messages.isEmpty {
        MailboxPager(mailbox: mailbox)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}
