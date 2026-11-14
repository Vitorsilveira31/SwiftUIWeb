import SwiftUIWeb

/// The navigation rail of a wide window: the mark, Home, and the button that opens the composer.
struct QuillRail: View {
  let onCompose: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      QuillLogo(size: 36).padding(.vertical, 12)
      Label(ShellStrings.home, systemImage: "house")
        .font(.title3)
        .fontWeight(.bold)
        .padding(.vertical, 8)
      Button { onCompose() } label: { Label(ShellStrings.compose, systemImage: "square.and.pencil") }
        .buttonStyle(.borderedProminent)
        .padding(.top, 12)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .frame(maxHeight: .infinity, alignment: .topLeading)
  }
}
