import SwiftUIWeb

/// The composer on a phone, or from the rail: a sheet with the field and a way to close it.
struct ComposerSheet: View {
  let viewModel: ComposerViewModel
  let posted: @MainActor @Sendable (QuillPost) -> Void
  let close: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Spacer()
        Button(ComposerStrings.close, action: close)
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
      ComposerView(viewModel: viewModel, posted: posted)
      Spacer()
    }
    .frame(minWidth: 320, minHeight: 220)
  }
}
