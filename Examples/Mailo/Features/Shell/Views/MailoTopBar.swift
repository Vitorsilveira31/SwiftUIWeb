import SwiftUIWeb

/// The brand, and the search that asks the service for the messages that match.
struct MailoTopBar: View {
  let mailbox: MailboxViewModel

  var body: some View {
    HStack(spacing: 12) {
      MailoLogo(size: 30)
      Text(ShellStrings.appName).font(.title3).fontWeight(.bold)
      TextField(ShellStrings.searchPrompt, text: Binding(get: { mailbox.query }, set: { mailbox.query = $0 }))
        .textFieldStyle(.roundedBorder)
        .onSubmit { Task { await mailbox.search() } }
        .frame(maxWidth: 520)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}
