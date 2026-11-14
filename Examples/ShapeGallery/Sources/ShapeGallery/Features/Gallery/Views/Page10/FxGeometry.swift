import SwiftUI

// Circles slide along a rail, bars rise, an ellipse swells. Positions are the values at
// each paused phase of the reference animation, so the picture needs no clock.
struct FxGeometry: View {
    var body: some View {
        FixtureTile(name: "fx-geometry") {
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 20, y: 16))
                    path.addLine(to: CGPoint(x: 100, y: 16))
                }
                .stroke(Color(hex: 0xCBD5E1), lineWidth: 1)
                Circle()
                    .fill(Color(hex: 0x2563EB))
                    .placed(60 - 8, 16 - 8, 16, 16)
                Circle()
                    .fill(Color(hex: 0xF59E0B))
                    .placed(28 - 4, 16 - 4, 8, 8)
                Rectangle()
                    .fill(Color(hex: 0x16A34A))
                    .placed(12, 57.5, 16, 8)
                Rectangle()
                    .fill(Color(hex: 0x16A34A))
                    .placed(36, 32.5, 16, 8)
                Ellipse()
                    .fill(Color(hex: 0xA855F7))
                    .placed(90 - 17, 56 - 10, 34, 20)
            }
        }
    }
}
