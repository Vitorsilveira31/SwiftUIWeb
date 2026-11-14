import SwiftUIWeb

/// The folders on a narrow screen: a row of them, with the button that starts a message first.
struct FolderChips: View {
  let app: MailoController

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        Button(ComposeStrings.compose) { app.startCompose() }
          .buttonStyle(.borderedProminent)
        ForEach(MailFolder.allCases) { folder in
          FolderRow(app: app, folder: folder)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
  }
}
