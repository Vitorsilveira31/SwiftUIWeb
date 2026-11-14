import SwiftUI

// Hatching: stripes turned by a pattern transform. The second is the first's
// stripes at another angle and width, and the ellipse's stroke takes the hatch's colour.
struct FxPatternHatch: View {
    var body: some View {
        FixtureTile(name: "fx-pattern-hatch") {
            ZStack(alignment: .topLeading) {
                Hatching(angle: 45, barWidth: 4, period: 8)
                    .fill(Color(hex: 0x334155))
                    .frame(width: 120, height: 80)
                    .mask {
                        Rectangle().placed(6, 6, 50, 68).pictureLayer()
                    }
                Hatching(angle: -30, barWidth: 2, period: 8)
                    .fill(Color(hex: 0x334155))
                    .frame(width: 120, height: 80)
                    .mask {
                        Ellipse().placed(90 - 24, 40 - 30, 48, 60).pictureLayer()
                    }
                Ellipse()
                    .stroke(Color(hex: 0x334155), lineWidth: 6)
                    .placed(90 - 24, 40 - 30, 48, 60)
            }
        }
    }
}
