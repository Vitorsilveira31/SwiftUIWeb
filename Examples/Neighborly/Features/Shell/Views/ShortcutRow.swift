import SwiftUIWeb

/// A shortcut in the left column: a symbol and a name, and a tap that goes there.
struct ShortcutRow: View {
  let title: String
  let symbol: String
  let action: @MainActor @Sendable () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}
