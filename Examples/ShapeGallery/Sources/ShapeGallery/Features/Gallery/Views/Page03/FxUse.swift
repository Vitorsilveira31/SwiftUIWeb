import SwiftUI

// One star symbol drawn three times, each in its own colour, plus a gradient
// turned 90 degrees (top to bottom) on a rounded bar.
struct FxUse: View {
    var body: some View {
        FixtureTile(name: "fx-use") {
            ZStack(alignment: .topLeading) {
                Star()
                    .fill(Color(hex: 0xF59E0B))
                    .placed(4, 6, 34, 34)
                Star()
                    .fill(Color(hex: 0x10B981))
                    .placed(43, 6, 34, 34)
                Star()
                    .fill(Color(hex: 0x6366F1))
                    .placed(82, 6, 34, 34)
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color(hex: 0xFDE047), location: 0),
                            Gradient.Stop(color: Color(hex: 0xCA8A04), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .placed(8, 48, 104, 26)
            }
        }
    }
}
