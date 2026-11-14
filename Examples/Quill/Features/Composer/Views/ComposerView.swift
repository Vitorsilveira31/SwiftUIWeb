import SwiftUIWeb

/// The field to write a post, the characters left and the button that posts it.
struct ComposerView: View {
  let viewModel: ComposerViewModel
  let posted: @MainActor @Sendable (QuillPost) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField(ComposerStrings.placeholder, text: Binding(get: { viewModel.draft }, set: { viewModel.draft = $0 }))
        .textFieldStyle(.roundedBorder)
        .onSubmit { Task { await viewModel.post(posted) } }
      HStack(spacing: 8) {
        Text(ComposerStrings.left(viewModel.remaining))
          .font(.caption)
          .foregroundStyle(viewModel.isOverLimit ? QuillPalette.like : Color.primary)
        Spacer()
        Button(ComposerStrings.post) { Task { await viewModel.post(posted) } }
          .buttonStyle(.borderedProminent)
          .disabled(!viewModel.canPost)
      }
      if viewModel.sendFailed {
        Text(ComposerStrings.sendFailed).font(.caption).foregroundStyle(.red)
      }
    }
    .padding(12)
  }
}
