import SwiftUI

// A grid tile: its icon is the matched zoom source, with an optional unread badge.
struct TileButton: View {
    let tile: Tile
    let zoom: Namespace.ID
    let isSource: Bool
    let badge: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                TileIcon(symbol: tile.symbol, size: 66)
                    .matchedGeometryEffect(id: tile.id, in: zoom, isSource: isSource)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 22, minHeight: 22)
                                .background(Color.orange, in: Capsule())
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(tile.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app-\(tile.id)")
    }
}
