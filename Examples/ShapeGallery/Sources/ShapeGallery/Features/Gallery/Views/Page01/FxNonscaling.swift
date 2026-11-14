import SwiftUI

// A stretched chart: the first line keeps its width, the second scales with the box.
struct FxNonscaling: View {
    var body: some View {
        FixtureTile(name: "fx-nonscaling") {
            ZStack(alignment: .topLeading) {
                Path { path in
                    let points: [CGPoint] = [
                        CGPoint(x: 0, y: 64), CGPoint(x: 24, y: 48), CGPoint(x: 48, y: 56),
                        CGPoint(x: 72, y: 24), CGPoint(x: 96, y: 32), CGPoint(x: 120, y: 8),
                    ]
                    path.addLines(points)
                }
                .stroke(Color(hex: 0x2563EB), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                Path { path in
                    let points: [CGPoint] = [
                        CGPoint(x: 0, y: 72), CGPoint(x: 24, y: 64), CGPoint(x: 48, y: 72),
                        CGPoint(x: 72, y: 48), CGPoint(x: 96, y: 56), CGPoint(x: 120, y: 40),
                    ]
                    path.addLines(points)
                }
                .stroke(Color(hex: 0x94A3B8), lineWidth: 3)
            }
        }
    }
}
