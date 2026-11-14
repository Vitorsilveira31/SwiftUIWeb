import SwiftUI

// An area chart: the fill starts at the line's top (y 14) and fades to nothing.
struct FxArea: View {
    private static let areaLine: [CGPoint] = [
        CGPoint(x: 0, y: 50), CGPoint(x: 20, y: 42), CGPoint(x: 40, y: 48),
        CGPoint(x: 60, y: 26), CGPoint(x: 80, y: 32), CGPoint(x: 100, y: 14),
        CGPoint(x: 120, y: 20),
    ]

    var body: some View {
        FixtureTile(name: "fx-area") {
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 80))
                    for point in Self.areaLine {
                        path.addLine(to: point)
                    }
                    path.addLine(to: CGPoint(x: 120, y: 80))
                    path.closeSubpath()
                }
                .fill(LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(hex: 0x2563EB, opacity: 0.45), location: 0),
                        Gradient.Stop(color: Color(hex: 0x2563EB, opacity: 0), location: 1),
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 14 / 80),
                    endPoint: .bottom
                ))
                Path { path in
                    path.addLines(Self.areaLine)
                }
                .stroke(Color(hex: 0x2563EB), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
    }
}
