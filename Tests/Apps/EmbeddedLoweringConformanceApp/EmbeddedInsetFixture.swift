import SwiftUIWeb

/// `safeAreaInset` on each edge and a TabView with its bottom tab bar, which the layout engines both lay out as an inset:
/// the inset takes its ideal size along its edge and is aligned across it, the content takes what is left.
/// CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedInsetFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      HStack(alignment: .top, spacing: 12) {
        panel("Top")
          .safeAreaInset(edge: .top, alignment: .leading, spacing: 6) { badge("Top inset") }
        panel("Bottom")
          .safeAreaInset(edge: .bottom, spacing: 4) { badge("Bottom inset") }
        panel("Leading")
          .safeAreaInset(edge: .leading, spacing: 8) { badge("L") }
        panel("Trailing")
          .safeAreaInset(edge: .trailing, alignment: .bottom) { badge("T") }
      }
      .frame(height: 160)
      TabView {
        Tab("First", systemImage: "1.circle") { Text("First tab content") }
        Tab("Second", systemImage: "2.circle") { Text("Second tab content") }
      }
      .frame(width: 320, height: 200)
    }
    .padding(16)
  }

  private func panel(_ title: String) -> some View {
    Text(title)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.gray.opacity(0.15))
  }

  private func badge(_ title: String) -> some View {
    Text(title)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color.blue.opacity(0.2))
  }
}
