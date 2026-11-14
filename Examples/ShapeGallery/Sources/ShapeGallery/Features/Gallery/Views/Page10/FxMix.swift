import SwiftUI

// Blend modes between shapes: multiply, screen, difference and luminosity over a
// bar, then an isolated group whose overlay stays inside it, and two that do not isolate.
struct FxMix: View {
    var body: some View {
        FixtureTile(name: "fx-mix") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0xF8FAFC))
                    .frame(width: 120, height: 80)
                Rectangle()
                    .fill(Color(hex: 0xF59E0B))
                    .placed(6, 10, 108, 24)
                Circle()
                    .fill(Color(hex: 0x2563EB))
                    .placed(22 - 14, 22 - 14, 28, 28)
                    .blendMode(.multiply)
                Circle()
                    .fill(Color(hex: 0x2563EB))
                    .placed(50 - 14, 22 - 14, 28, 28)
                    .blendMode(.screen)
                Circle()
                    .fill(Color(hex: 0x2563EB))
                    .placed(78 - 14, 22 - 14, 28, 28)
                    .blendMode(.difference)
                Circle()
                    .fill(Color(hex: 0x2563EB))
                    .placed(104 - 14, 22 - 14, 28, 28)
                    .blendMode(.luminosity)
                Rectangle()
                    .fill(Color(hex: 0x16A34A))
                    .placed(6, 46, 108, 28)
                ZStack(alignment: .topLeading) {
                    Circle()
                        .fill(Color(hex: 0xEF4444))
                        .placed(40 - 12, 60 - 12, 24, 24)
                    Circle()
                        .fill(Color(hex: 0x3B82F6))
                        .placed(52 - 12, 60 - 12, 24, 24)
                        .blendMode(.overlay)
                }
                .pictureLayer()
                .compositingGroup()
                Circle()
                    .fill(Color(hex: 0xEF4444))
                    .placed(84 - 12, 60 - 12, 24, 24)
                Circle()
                    .fill(Color(hex: 0x3B82F6))
                    .placed(96 - 12, 60 - 12, 24, 24)
                    .blendMode(.overlay)
            }
        }
    }
}
