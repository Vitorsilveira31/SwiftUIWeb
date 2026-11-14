import SwiftUI

// Phases: shift at 50% (red to blue), ink at 25% (green to amber), fadeTo at 50%
// (red to a 20% blue), shift at about 75% with an ease curve. Each is written out at its
// paused value, so the picture needs no clock.
struct FxColor: View {
    var body: some View {
        FixtureTile(name: "fx-color") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0x8A5498))
                    .placed(8, 8, 48, 30)
                Path { path in
                    path.move(to: CGPoint(x: 64, y: 34))
                    path.addLine(to: CGPoint(x: 80, y: 10))
                    path.addLine(to: CGPoint(x: 96, y: 30))
                    path.addLine(to: CGPoint(x: 112, y: 8))
                }
                .stroke(Color(hex: 0x4EA23A), lineWidth: 4)
                Rectangle()
                    .fill(Color(hex: 0x8A5498, opacity: 0.6))
                    .placed(8, 44, 48, 30)
                Circle()
                    .fill(Color(hex: 0x3960DA))
                    .placed(88 - 14, 60 - 14, 28, 28)
            }
        }
    }
}
