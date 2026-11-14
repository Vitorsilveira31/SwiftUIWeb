import SwiftUI

struct FxAxis: View {
    var body: some View {
        FixtureTile(name: "fx-axis") {
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 10, y: 56))
                    path.addLine(to: CGPoint(x: 110, y: 56))
                    path.move(to: CGPoint(x: 10, y: 56))
                    path.addLine(to: CGPoint(x: 10, y: 60))
                    path.move(to: CGPoint(x: 60, y: 56))
                    path.addLine(to: CGPoint(x: 60, y: 60))
                    path.move(to: CGPoint(x: 110, y: 56))
                    path.addLine(to: CGPoint(x: 110, y: 60))
                }
                .stroke(Color(hex: 0x94A3B8), lineWidth: 1)
                AnchoredLabel("0", x: 10, y: 70, size: 9, color: Color(hex: 0x475569), anchor: .middle)
                AnchoredLabel("50", x: 60, y: 70, size: 9, color: Color(hex: 0x475569), anchor: .middle)
                AnchoredLabel("100", x: 110, y: 70, size: 9, color: Color(hex: 0x475569), anchor: .end)
                AnchoredLabel(
                    "Revenue", x: 60, y: 30, size: 16, weight: .semibold,
                    color: Color(hex: 0x0F172A), anchor: .middle
                )
            }
        }
    }
}
