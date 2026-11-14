import SwiftUI

// An arrowhead on a line, and a dot at every vertex of a line chart.
struct FxArrows: View {
    private static let chartPoints: [CGPoint] = [
        CGPoint(x: 10, y: 70), CGPoint(x: 35, y: 40), CGPoint(x: 60, y: 55),
        CGPoint(x: 85, y: 30), CGPoint(x: 110, y: 45),
    ]

    var body: some View {
        FixtureTile(name: "fx-arrows") {
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 10, y: 18))
                    path.addLine(to: CGPoint(x: 100, y: 18))
                }
                .stroke(Color(hex: 0x0F172A), lineWidth: 2)
                // Marker 5 x 2 stroke = 10 points, the tip two points past the line's end.
                Arrowhead(centre: CGPoint(x: 97, y: 18), direction: CGPoint(x: 1, y: 0), length: 10)
                    .fill(Color(hex: 0x0F172A))

                Path { path in
                    path.addLines(Self.chartPoints)
                }
                .stroke(Color(hex: 0x2563EB), style: StrokeStyle(lineWidth: 2))
                ForEach(Self.chartPoints.indices, id: \.self) { index in
                    MarkerDot(point: Self.chartPoints[index])
                }
            }
        }
    }
}
