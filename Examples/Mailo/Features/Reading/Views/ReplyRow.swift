import SwiftUIWeb

/// One reply: the author's initials, the author's name and the text.
struct ReplyRow: View {
  let reply: MailReply

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      MailoAvatar(person: reply.author, size: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(reply.author.name).font(.caption).fontWeight(Font.Weight.bold)
        Text(reply.body)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
