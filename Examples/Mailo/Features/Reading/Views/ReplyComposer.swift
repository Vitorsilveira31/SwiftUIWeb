import SwiftUIWeb

/// The box to reply in, and the button that posts the reply as a comment.
struct ReplyComposer: View {
  let reading: ReadingViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        TextField(ReadingStrings.placeholder, text: Binding(get: { reading.draft }, set: { reading.draft = $0 }))
          .textFieldStyle(.roundedBorder)
          .onSubmit { Task { await reading.send() } }
        Button(ReadingStrings.reply) { Task { await reading.send() } }
          .buttonStyle(.borderedProminent)
          .disabled(!reading.canSend || reading.isSending)
      }
      if reading.replyFailed {
        Text(ReadingStrings.replyFailed).font(.caption).foregroundStyle(.red)
      }
    }
  }
}
