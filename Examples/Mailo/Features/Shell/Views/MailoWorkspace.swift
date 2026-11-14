import SwiftUIWeb

/// The two layouts of the mail. Wide: the folders, the list and the reading pane side by side. Narrow: one at a time, the folders
/// above the list, and a message replaces the list with a way back to it.
struct MailoWorkspace: View {
  let app: MailoController
  let wide: Bool

  var body: some View {
    if wide {
      HStack(alignment: .top, spacing: 0) {
        FolderSidebar(app: app)
          .frame(width: MailoLayout.folderWidth)
        Divider()
        MailboxView(app: app)
          .frame(width: MailoLayout.listWidth)
        Divider()
        if let reader = app.reader {
          ReadingPane(app: app, reading: reader, narrow: false)
        } else {
          Text(ReadingStrings.empty)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let reader = app.reader {
      ReadingPane(app: app, reading: reader, narrow: true)
    } else {
      VStack(spacing: 0) {
        FolderChips(app: app)
        Divider()
        MailboxView(app: app)
      }
    }
  }
}
