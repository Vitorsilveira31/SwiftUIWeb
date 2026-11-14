import SwiftUIWeb

/// The subject, who wrote the message and when, and the actions: a way back on a phone, the star and the delete.
struct ReadingHeader: View {
  let app: MailoController
  let reading: ReadingViewModel
  let narrow: Bool

  var body: some View {
    let message = reading.message
    let starred = app.mailbox.memory.isStarred(message.id)
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        if narrow {
          Button(ReadingStrings.back) { app.closeReader() }
            .buttonStyle(.plain)
        }
        Spacer()
        Button(starred ? ReadingStrings.unstar : ReadingStrings.star) { app.mailbox.toggleStar(message.id) }
          .buttonStyle(.bordered)
        Button(ReadingStrings.delete) { Task { await app.delete([message.id]) } }
          .buttonStyle(.bordered)
      }
      Text(message.subject.isEmpty ? MailboxStrings.noSubject : message.subject)
        .font(.title3)
        .fontWeight(Font.Weight.bold)
      HStack(alignment: .top, spacing: 12) {
        MailoAvatar(person: message.sender, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(message.sender.name).fontWeight(Font.Weight.bold)
          Text(message.sender.address).font(.caption).foregroundStyle(.secondary)
          if let recipient = message.recipient {
            Text(MailboxStrings.to(recipient)).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        Text(MailTime.label(for: message.id)).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(16)
  }
}
