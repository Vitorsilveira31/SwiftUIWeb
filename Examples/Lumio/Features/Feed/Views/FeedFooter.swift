import SwiftUIWeb

/// The end of the posts so far: a way to ask for more, a spinner while it comes, or the note that there is no more.
struct FeedFooter: View {
  let viewModel: FeedViewModel

  var body: some View {
    Group {
      if viewModel.isLoadingMore {
        ProgressView()
      } else if viewModel.reachedEnd {
        Text(FeedStrings.endOfFeed).foregroundStyle(.secondary)
      } else {
        Button(FeedStrings.loadMore) { Task { await viewModel.loadMore() } }.buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }
}
