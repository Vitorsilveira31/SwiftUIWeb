import SwiftUIWeb

/// The bar at the bottom of a phone: Home, and the button that opens the composer.
struct QuillBottomBar: View {
  let onCompose: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Divider()
      HStack {
        Image(systemName: "house").fontWeight(.bold)
        Spacer()
        Button { onCompose() } label: { Image(systemName: "square.and.pencil") }
          .accessibilityLabel(ShellStrings.compose)
      }
      .font(.title3)
      .buttonStyle(.plain)
      .padding(.horizontal, 28)
      .padding(.vertical, 10)
    }
  }
}
