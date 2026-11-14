import SwiftUIWeb

/// One reply: who wrote it, then what they said.
struct ReplyRow: View {
  let reply: QuillReply

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      QuillAvatar(url: reply.avatarURL, label: reply.name, size: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(reply.name).font(.subheadline).fontWeight(.semibold)
        Text(reply.text).font(.callout)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 10)
  }
}
