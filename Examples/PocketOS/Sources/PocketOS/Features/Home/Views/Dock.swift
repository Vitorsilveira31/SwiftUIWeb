import SwiftUI

// The dock along the bottom of the home screen: the four items that stay in reach.
struct Dock: View {
    let items: [Tile]
    let shell: ShellViewModel

    var body: some View {
        HStack(spacing: 20) {
            ForEach(items) { item in
                Button {
                    shell.send(.activate(item.target, name: item.title))
                } label: {
                    TileIcon(symbol: item.symbol, size: 62)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier("dock-\(item.id)")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}
