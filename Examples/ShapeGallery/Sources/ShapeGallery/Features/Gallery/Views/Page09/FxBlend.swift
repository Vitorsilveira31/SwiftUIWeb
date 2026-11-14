import SwiftUI

// Blend and arithmetic composite, in one picture: multiply, screen, and an even mix.
struct FxBlend: View {
    var body: some View {
        FixtureTile(name: "fx-blend") {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color(hex: 0xFDE047))
                    Rectangle().fill(Color(hex: 0x38BDF8)).blendMode(.multiply)
                }
                .placed(6, 8, 32, 64)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color(hex: 0x16A34A))
                    Rectangle().fill(Color(hex: 0x7C3AED)).blendMode(.screen)
                }
                .placed(44, 8, 32, 64)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color(hex: 0x2563EB))
                    Rectangle().fill(Color(hex: 0xEF4444)).opacity(0.5)
                }
                .placed(82, 8, 32, 64)
            }
        }
    }
}
