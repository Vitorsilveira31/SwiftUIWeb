import SwiftUI

// One rectangle, filled with a radial gradient that fades at its edge, and a
// violet rectangle that fades to the right.
struct FxMaskGradient: View {
    var body: some View {
        FixtureTile(name: "fx-mask-gradient") {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(hex: 0x0EA5E9))
                        .placed(0, 0, 70, 80)
                    Circle()
                        .fill(Color(hex: 0xF59E0B))
                        .placed(35 - 18, 40 - 18, 36, 36)
                }
                .pictureLayer()
                .mask {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(RadialGradient(
                                colors: [.white, .white.opacity(0)],
                                center: .center, startRadius: 15, endRadius: 38
                            ))
                            .placed(0, 0, 70, 80)
                    }
                    .pictureLayer()
                }
                Rectangle()
                    .fill(Color(hex: 0x7C3AED))
                    .placed(76, 8, 40, 64)
                    .mask {
                        LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    }
            }
        }
    }
}
