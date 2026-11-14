import SwiftUI

// The shadow's deviation and offset are in the user space, so under a 3x view box
// they are three times larger on screen. The square is turned about its centre.
struct FxShadowScaled: View {
    var body: some View {
        FixtureTile(name: "fx-shadow-scaled") {
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Color(hex: 0xF59E0B))
                    .placed(33 - 18, 39 - 18, 36, 36)
                    .shadow(color: Color(hex: 0x1E3A8A, opacity: 0.7), radius: 3, x: 3, y: 4.5)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(hex: 0x10B981))
                        .placed(72, 24, 30, 30)
                        .shadow(color: Color(hex: 0x111827), radius: 2.4, x: 3, y: 3)
                }
                .pictureLayer()
                .rotationEffect(.degrees(30), anchor: UnitPoint(x: 87 / 120, y: 39 / 80))
            }
        }
    }
}
