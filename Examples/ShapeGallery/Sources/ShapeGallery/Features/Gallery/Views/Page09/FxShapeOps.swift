import SwiftUI

// Morphology (dilate, erode), component transfer (posterise) and tile, drawn as the
// shapes they produce.
struct FxShapeOps: View {
    var body: some View {
        FixtureTile(name: "fx-shape-ops") {
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 10, y: 40))
                    path.addLine(to: CGPoint(x: 26, y: 14))
                    path.addLine(to: CGPoint(x: 42, y: 40))
                    path.closeSubpath()
                }
                .stroke(Color(hex: 0x1D4ED8), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
                Rectangle()
                    .fill(Color(hex: 0x1D4ED8))
                    .placed(51.5, 12.5, 21, 29)
                Rectangle()
                    .fill(Color(hex: 0x801942, opacity: 0.8))
                    .placed(82, 12, 32, 30)
                Rectangle()
                    .fill(Color(hex: 0xF43F5E))
                    .placed(10, 50, 100, 24)
            }
        }
    }
}
