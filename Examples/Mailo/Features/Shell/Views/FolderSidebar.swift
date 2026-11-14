import SwiftUIWeb

/// The folders, with the unread count of the inbox, under the button that starts a message.
struct FolderSidebar: View {
  let app: MailoController

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button(ComposeStrings.compose) { app.startCompose() }
        .buttonStyle(.borderedProminent)
        .padding(.bottom, 12)
      ForEach(MailFolder.allCases) { folder in
        FolderRow(app: app, folder: folder)
      }
      Spacer()
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.white)
  }
}
