import SwiftUI

// CSS drop-shadow() on shapes, one under a blur.
struct FxDropShadowCss: View {
    var body: some View {
        FixtureTile(name: "fx-drop-shadow-css") {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: 0xF59E0B))
                    .placed(14, 10, 40, 30)
                    .shadow(color: Color(hex: 0x000000, opacity: 0.6), radius: 8, x: 0, y: 6)
                Circle()
                    .fill(Color(hex: 0x0EA5E9))
                    .placed(72, 14, 32, 32)
                    .blur(radius: 1.5)
                    .shadow(color: Color(hex: 0x1E3A8A), radius: 6, x: 4, y: 4)
                Rectangle()
                    .fill(Color(hex: 0x10B981))
                    .placed(30, 58, 60, 14)
                    .shadow(color: Color(hex: 0xBE185D, opacity: 0.9), radius: 3, x: -6, y: -2)
            }
        }
    }
}
