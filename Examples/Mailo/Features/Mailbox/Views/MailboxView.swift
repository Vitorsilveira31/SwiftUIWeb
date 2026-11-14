import SwiftUIWeb

/// The list of the folder: its toolbar, then one page of its messages, or the state it is in (loading, failed, empty).
struct MailboxView: View {
  let app: MailoController

  var body: some View {
    let mailbox = app.mailbox
    VStack(spacing: 0) {
      MailboxToolbar(app: app)
      Divider()
      ScrollView {
        switch mailbox.state {
        case .loading, .failed:
          MailoStatusView(state: mailbox.state, loading: MailboxStrings.loading, failedTitle: MailboxStrings.failedTitle, retry: MailboxStrings.retry) {
            Task { await mailbox.load() }
          }
        case .loaded:
          if mailbox.messages.isEmpty {
            Text(MailboxStrings.empty(mailbox.folder))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 40)
          } else {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(mailbox.pageMessages) { message in
                MailboxRow(app: app, message: message)
                Divider()
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
