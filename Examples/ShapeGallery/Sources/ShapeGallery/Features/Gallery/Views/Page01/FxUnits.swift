import SwiftUI

// Percentages are of the 120 x 80 picture; the circle's radius is 10% of the
// diagonal, sqrt((120^2 + 80^2) / 2), about 102.
struct FxUnits: View {
    var body: some View {
        FixtureTile(name: "fx-units") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0xF59E0B))
                    .placed(12, 8, 96, 24)
                Path { path in
                    path.move(to: CGPoint(x: 12, y: 48))
                    path.addLine(to: CGPoint(x: 108, y: 48))
                }
                .stroke(Color(hex: 0x0F172A), lineWidth: 2)
                Circle()
                    .fill(Color(hex: 0x6366F1))
                    .placed(60 - 10.2, 64 - 10.2, 20.4, 20.4)
                Rectangle()
                    .fill(Color(hex: 0x10B981))
                    .placed(24, 46, 16, 15.1)
            }
        }
    }
}
