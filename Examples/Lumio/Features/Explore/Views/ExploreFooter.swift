import SwiftUIWeb

/// Below the grid: a way to ask for more pictures, or a spinner while they come.
struct ExploreFooter: View {
  let viewModel: ExploreViewModel

  var body: some View {
    Group {
      if viewModel.isLoadingMore {
        ProgressView()
      } else if !viewModel.reachedEnd {
        Button(ExploreStrings.loadMore) { Task { await viewModel.loadMore() } }.buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
  }
}
