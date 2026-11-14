import SwiftUIWeb

/// One message in the list: its checkbox, its star, and the sender, the subject, the preview and the time. A received message is bold while unread.
struct MailboxRow: View {
  let app: MailoController
  let message: MailMessage

  var body: some View {
    let mailbox = app.mailbox
    let unread = mailbox.memory.isUnread(message)
    let starred = mailbox.memory.isStarred(message.id)
    let weight = unread ? Font.Weight.bold : Font.Weight.regular
    HStack(alignment: .top, spacing: 10) {
      Toggle(isOn: Binding(get: { mailbox.isSelected(message.id) }, set: { _ in mailbox.toggleSelection(message.id) })) {
        EmptyView()
      }
      .toggleStyle(.checkbox)
      .accessibilityLabel(MailboxStrings.select)
      Button {
        mailbox.toggleStar(message.id)
      } label: {
        Text(starred ? "★" : "☆").foregroundStyle(MailoPalette.star)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(starred ? MailboxStrings.unstar : MailboxStrings.star)
      Button {
        app.open(message)
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 8) {
            Text(counterpart).fontWeight(weight).lineLimit(1)
            Spacer()
            Text(timeLabel).font(.caption).foregroundStyle(.secondary)
          }
          Text(subject).fontWeight(weight).lineLimit(1)
          Text(message.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(mailbox.isSelected(message.id) ? MailoPalette.selection : Color.white)
  }

  /// Who the row is about: the recipient of a sent message, the sender of a received one.
  private var counterpart: String {
    if message.isDraft { return MailboxStrings.draft }
    if message.isMine, let recipient = message.recipient { return MailboxStrings.to(recipient) }
    return message.sender.name
  }

  private var timeLabel: String { message.isDraft ? MailboxStrings.draft : MailTime.label(for: message.id) }

  private var subject: String { message.subject.isEmpty ? MailboxStrings.noSubject : message.subject }
}
