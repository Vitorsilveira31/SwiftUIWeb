import SwiftUIWeb

/// Home: the stories and the posts, a page at a time, with the comments of a post in a sheet.
struct FeedView: View {
  let viewModel: FeedViewModel

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        StoriesRow(people: viewModel.stories)
        Divider()
        if viewModel.state == .loaded {
          ForEach(viewModel.posts) { post in
            PostCard(viewModel: viewModel, post: post)
          }
          FeedFooter(viewModel: viewModel)
        } else {
          LumioStatusView(state: viewModel.state, loading: FeedStrings.loading, failedTitle: FeedStrings.failedTitle, retry: FeedStrings.retry) {
            Task { await viewModel.load() }
          }
        }
      }
      .frame(maxWidth: LumioLayout.feedWidth)
      .frame(maxWidth: .infinity)
    }
    .task { if viewModel.posts.isEmpty { await viewModel.load() } }
    .sheet(item: Binding(get: { viewModel.commenting }, set: { viewModel.commenting = $0 })) { post in
      CommentsSheet(viewModel: viewModel.commentsModel(for: post), post: post) { viewModel.commenting = nil }
    }
  }
}
