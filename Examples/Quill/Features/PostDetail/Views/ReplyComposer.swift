import SwiftUIWeb

/// The field to write a reply and the button that sends it.
struct ReplyComposer: View {
  let viewModel: PostDetailViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        TextField(PostDetailStrings.placeholder, text: Binding(get: { viewModel.draft }, set: { viewModel.draft = $0 }))
          .textFieldStyle(.roundedBorder)
          .onSubmit { Task { await viewModel.send() } }
        Button(PostDetailStrings.send) { Task { await viewModel.send() } }
          .buttonStyle(.borderedProminent)
          .disabled(!viewModel.canSend)
      }
      if viewModel.sendFailed {
        Text(PostDetailStrings.sendFailed).font(.caption).foregroundStyle(.red)
      }
    }
  }
}
