import SwiftUI

// One fixture: a 120 x 80 picture on a light card, captioned with its name. The name is also
// the accessibility identifier, so a test can find the tile.
struct FixtureTile<Picture: View>: View {
    let name: String
    @ViewBuilder var picture: Picture

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Color(hex: 0xF8FAFC)
                picture
            }
            .frame(width: 120, height: 80)
            .clipped()
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 120)
        }
        .frame(width: 120)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(name)
    }
}
