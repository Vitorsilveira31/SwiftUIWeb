import SwiftUIWeb

/// The searches made in this visit, newest first; a click runs one again.
struct SeekrRecentSearches: View {
  let shell: SeekrShellViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !shell.recent.isEmpty {
        Text(HomeStrings.recent).font(.caption).foregroundStyle(.secondary)
        ForEach(shell.recent, id: \.self) { text in
          Button(text) { Task { await shell.submit(text) } }
            .buttonStyle(.plain)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
