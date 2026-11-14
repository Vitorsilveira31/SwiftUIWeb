import SwiftUIWeb

/// One item of the bottom bar: a symbol above its name, in the brand's color when it is the screen on.
struct BottomBarItem: View {
  let title: String
  let symbol: String
  let selected: Bool
  let action: @MainActor @Sendable () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: symbol).font(.title3)
        Text(title).font(.caption2)
      }
      .foregroundStyle(selected ? NeighborlyPalette.teal : Color.primary)
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}
