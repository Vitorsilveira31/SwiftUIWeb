import SwiftUIWeb

/// The results screen: the bar with the search box and the tabs, then the list of the open tab.
struct SeekrResultsView: View {
  let shell: SeekrShellViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SeekrResultsHeader(shell: shell)
      Divider()
      ScrollView {
        Group {
          if shell.results.tab == .images {
            SeekrImagesView(viewModel: shell.images)
          } else {
            SeekrWebResults(shell: shell)
          }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: SeekrLayout.resultsWidth)
        .frame(maxWidth: .infinity)
      }
    }
  }
}
