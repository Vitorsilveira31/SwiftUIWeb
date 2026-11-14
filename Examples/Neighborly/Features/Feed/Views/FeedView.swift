import SwiftUIWeb

/// Home: the composer, the group in view and the posts, a page at a time. A post's comments open under it.
struct FeedView: View {
  let viewModel: FeedViewModel
  let openPerson: @MainActor @Sendable (Int) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        PostComposer(viewModel: viewModel)
        if let group = viewModel.group {
          GroupBanner(viewModel: viewModel, city: group)
        }
        if viewModel.state == .loaded {
          if viewModel.visiblePosts.isEmpty {
            Text(viewModel.group == nil ? FeedStrings.empty : FeedStrings.emptyGroup)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 32)
          }
          ForEach(viewModel.visiblePosts) { post in
            PostCard(viewModel: viewModel, post: post, openPerson: openPerson)
          }
          FeedFooter(viewModel: viewModel)
        } else {
          NeighborlyStatusView(state: viewModel.state, loading: FeedStrings.loading, failedTitle: FeedStrings.failedTitle, retry: FeedStrings.retry) {
            Task { await viewModel.load() }
          }
        }
      }
      .padding(.vertical, 12)
      .frame(maxWidth: NeighborlyLayout.feedWidth)
      .frame(maxWidth: .infinity)
    }
  }
}
