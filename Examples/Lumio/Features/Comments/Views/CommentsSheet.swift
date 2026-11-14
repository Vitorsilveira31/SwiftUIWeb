import SwiftUIWeb

/// A post's comments, with the field to add one.
struct CommentsSheet: View {
  @State private var viewModel: CommentsViewModel
  let post: LumioPost
  let close: @MainActor @Sendable () -> Void

  init(viewModel: CommentsViewModel, post: LumioPost, close: @escaping @MainActor @Sendable () -> Void) {
    _viewModel = State(wrappedValue: viewModel)
    self.post = post
    self.close = close
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(CommentsStrings.title).font(.headline)
        Spacer()
        Button(CommentsStrings.close, action: close)
      }
      ScrollView {
        if viewModel.state == .loaded {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.comments) { comment in CommentRow(comment: comment) }
          }
        } else {
          LumioStatusView(state: viewModel.state, loading: CommentsStrings.loading, failedTitle: CommentsStrings.failed, retry: CommentsStrings.retry) {
            Task { await viewModel.loadComments() }
          }
        }
      }
      CommentComposer(viewModel: viewModel)
    }
    .padding(16)
    .frame(minWidth: 320, minHeight: 360)
    .task { await viewModel.loadComments() }
  }
}
