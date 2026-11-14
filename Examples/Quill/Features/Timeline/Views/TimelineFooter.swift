import SwiftUIWeb

/// The end of the posts so far: the note that there are none, a spinner while the next page comes, the note that there is no more, or a way to ask for more.
struct TimelineFooter: View {
  let viewModel: TimelineViewModel

  var body: some View {
    Group {
      if viewModel.posts.isEmpty {
        Text(TimelineStrings.empty).foregroundStyle(.secondary)
      } else if viewModel.isLoadingMore {
        ProgressView()
      } else if viewModel.reachedEnd {
        Text(TimelineStrings.caughtUp).foregroundStyle(.secondary)
      } else {
        Button(TimelineStrings.showMore) { Task { await viewModel.loadMore() } }.buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }
}
