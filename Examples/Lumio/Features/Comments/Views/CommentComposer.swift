import SwiftUIWeb

/// The field to write a comment and the button that sends it.
struct CommentComposer: View {
  let viewModel: CommentsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        TextField(CommentsStrings.placeholder, text: Binding(get: { viewModel.draft }, set: { viewModel.draft = $0 }))
          .textFieldStyle(.roundedBorder)
          .onSubmit { Task { await viewModel.send() } }
        Button(CommentsStrings.post) { Task { await viewModel.send() } }
          .buttonStyle(.borderedProminent)
          .disabled(!viewModel.canSend || viewModel.isSending)
      }
      if viewModel.sendFailed {
        Text(CommentsStrings.sendFailed).font(.caption).foregroundStyle(.red)
      }
    }
  }
}
