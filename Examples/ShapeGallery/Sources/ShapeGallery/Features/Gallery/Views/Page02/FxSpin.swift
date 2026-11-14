import SwiftUI

// A square turned 45 degrees about its centre; a group whose colour and dash
// phase are mid-way, so its children draw in the blended colour.
struct FxSpin: View {
    private let tint = Color(hex: 0x635588)

    var body: some View {
        FixtureTile(name: "fx-spin") {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(hex: 0x0EA5E9))
                        .placed(20, 20, 40, 40)
                }
                .pictureLayer()
                .rotationEffect(.degrees(45), anchor: UnitPoint(x: 40 / 120, y: 40 / 80))

                Circle()
                    .stroke(Color(hex: 0x0F172A), style: dashed)
                    .background(Circle().fill(tint))
                    .placed(90 - 12, 24 - 12, 24, 24)
                Path { path in
                    path.move(to: CGPoint(x: 70, y: 60))
                    path.addLine(to: CGPoint(x: 112, y: 60))
                }
                .stroke(Color(hex: 0x0F172A), style: dashed)
            }
        }
    }

    // A 4-on, 4-off dash, its phase at the midpoint of the march (6 of 12).
    private var dashed: StrokeStyle {
        StrokeStyle(lineWidth: 2, dash: [4, 4], dashPhase: 6)
    }
}
