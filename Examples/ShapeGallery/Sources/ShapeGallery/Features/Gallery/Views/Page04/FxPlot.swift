import SwiftUI

// A chart's plot area: the lines that overshoot it are cut at its edges.
struct FxPlot: View {
    var body: some View {
        FixtureTile(name: "fx-plot") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0xF1F5F9))
                    .placed(10, 10, 100, 60)
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.addLines([
                            CGPoint(x: 0, y: 70), CGPoint(x: 20, y: 40), CGPoint(x: 40, y: 55),
                            CGPoint(x: 60, y: 5), CGPoint(x: 80, y: 30), CGPoint(x: 100, y: -10),
                            CGPoint(x: 130, y: 40),
                        ])
                    }
                    .stroke(Color(hex: 0x2563EB), lineWidth: 3)
                    Circle()
                        .fill(Color(hex: 0xF97316))
                        .placed(100, 52, 24, 24)
                }
                .pictureLayer()
                .mask(alignment: .topLeading) {
                    Rectangle().placed(10, 10, 100, 60)
                }
            }
        }
    }
}
