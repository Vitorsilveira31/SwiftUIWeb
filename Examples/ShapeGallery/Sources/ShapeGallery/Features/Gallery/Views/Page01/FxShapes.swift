import SwiftUI

struct FxShapes: View {
    var body: some View {
        FixtureTile(name: "fx-shapes") {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: 0x0EA5E9))
                    .placed(8, 8, 40, 28)
                Ellipse()
                    .fill(Color(hex: 0xA855F7))
                    .placed(58, 8, 52, 28)
                Circle()
                    .stroke(Color(hex: 0x16A34A), lineWidth: 4)
                    .placed(14, 44, 28, 28)
                Path { path in
                    path.move(to: CGPoint(x: 52, y: 46))
                    path.addLine(to: CGPoint(x: 112, y: 72))
                }
                .stroke(Color(hex: 0x0F172A), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Path { path in
                    path.move(to: CGPoint(x: 60, y: 72))
                    path.addLine(to: CGPoint(x: 72, y: 48))
                    path.addLine(to: CGPoint(x: 84, y: 72))
                    path.closeSubpath()
                }
                .fill(Color(hex: 0xEF4444), style: FillStyle(eoFill: true))
            }
        }
    }
}
