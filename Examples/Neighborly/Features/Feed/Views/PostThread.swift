import SwiftUIWeb

/// The comments under a post: the ones loaded, a spinner or the failure while they load, and the field to write one.
struct PostThread: View {
  let viewModel: PostThreadViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if viewModel.state == .loaded {
        ForEach(viewModel.comments) { comment in ThreadRow(comment: comment) }
      } else {
        NeighborlyStatusView(state: viewModel.state, loading: FeedStrings.loadingComments, failedTitle: FeedStrings.commentsFailed, retry: FeedStrings.retry, padding: 16) {
          Task { await viewModel.load() }
        }
      }
      ThreadComposer(viewModel: viewModel)
    }
  }
}
