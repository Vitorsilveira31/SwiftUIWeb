import SwiftUIWeb

/// The bar above the results: the wordmark (a click goes home), the search box with the query kept in it, and the tabs.
struct SeekrResultsHeader: View {
  let shell: SeekrShellViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 16) {
        Button { shell.goHome() } label: {
          SeekrWordmark(size: 24)
        }
        .buttonStyle(.plain)
        SeekrSearchBox(shell: shell)
      }
      SeekrTabs(results: shell.results)
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
  }
}
