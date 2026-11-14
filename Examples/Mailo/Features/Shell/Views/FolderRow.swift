import SwiftUIWeb

/// One folder in the sidebar: its name, and the unread count for the inbox.
struct FolderRow: View {
  let app: MailoController
  let folder: MailFolder

  var body: some View {
    let selected = app.mailbox.folder == folder
    let unread = folder == .inbox ? app.mailbox.unreadCount : 0
    Button {
      Task { await app.select(folder) }
    } label: {
      HStack {
        Text(MailboxStrings.title(folder))
          .fontWeight(selected || unread > 0 ? Font.Weight.bold : Font.Weight.regular)
        Spacer()
        if unread > 0 {
          Text("\(unread)").fontWeight(Font.Weight.bold).foregroundStyle(MailoPalette.sea)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .background(selected ? MailoPalette.selection : Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}
