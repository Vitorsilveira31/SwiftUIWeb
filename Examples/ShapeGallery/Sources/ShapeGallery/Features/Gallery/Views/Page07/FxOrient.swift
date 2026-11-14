import SwiftUI

// Both ends of a curve get a head that turns with the curve (the start one is
// reversed), a tick at a polygon's vertices, and squares at a polyline's vertices.
struct FxOrient: View {
    private static let polygon: [CGPoint] = [
        CGPoint(x: 20, y: 50), CGPoint(x: 50, y: 70), CGPoint(x: 14, y: 74), CGPoint(x: 20, y: 50),
    ]
    private static let polyline: [CGPoint] = [CGPoint(x: 70, y: 70), CGPoint(x: 90, y: 52), CGPoint(x: 110, y: 70)]

    var body: some View {
        FixtureTile(name: "fx-orient") {
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 12, y: 34))
                    path.addCurve(
                        to: CGPoint(x: 70, y: 24),
                        control1: CGPoint(x: 30, y: 4),
                        control2: CGPoint(x: 60, y: 4)
                    )
                    // The arc's sweep-flag is 1 (clockwise on screen), through the top of the half circle.
                    path.addArc(
                        center: CGPoint(x: 85, y: 27), radius: 15.3,
                        startAngle: .degrees(-169), endAngle: .degrees(11), clockwise: false
                    )
                }
                .stroke(Color(hex: 0xDC2626), lineWidth: 2)
                // Heads: marker size 4 x 2 = 8 points, centred on each end.
                Arrowhead(centre: CGPoint(x: 12, y: 34), direction: CGPoint(x: -0.51, y: 0.86), length: 8)
                    .fill(Color(hex: 0xDC2626))
                Arrowhead(centre: CGPoint(x: 100, y: 30), direction: CGPoint(x: -0.19, y: 0.98), length: 8)
                    .fill(Color(hex: 0xDC2626))

                Path { path in
                    path.addLines(Self.polygon)
                }
                .fill(Color(hex: 0xBBF7D0))
                Path { path in
                    path.addLines(Self.polygon)
                }
                .stroke(Color(hex: 0x16A34A), lineWidth: 1)
                ForEach([CGPoint(x: 20, y: 50), CGPoint(x: 50, y: 70)], id: \.x) { point in
                    Rectangle()
                        .fill(Color(hex: 0x16A34A))
                        .frame(width: 6, height: 2)
                        .position(x: point.x, y: point.y)
                }

                Path { path in
                    path.addLines(Self.polyline)
                }
                .stroke(Color(hex: 0xA855F7), lineWidth: 2)
                ForEach(Self.polyline, id: \.x) { point in
                    Rectangle()
                        .fill(Color(hex: 0xA855F7))
                        .frame(width: 6, height: 6)
                        .rotationEffect(.degrees(45))
                        .position(x: point.x, y: point.y)
                }
            }
        }
    }
}
