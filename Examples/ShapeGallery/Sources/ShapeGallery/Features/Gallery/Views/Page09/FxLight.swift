import SwiftUI

// Diffuse lighting from the top-left (a warm disc) and specular glint from a point
// light (a white highlight over a red rounded square).
struct FxLight: View {
    var body: some View {
        FixtureTile(name: "fx-light") {
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(hex: 0xFEF9C3), Color(hex: 0xFDE68A), Color(hex: 0xB45309)],
                        center: UnitPoint(x: 0.3, y: 0.3), startRadius: 2, endRadius: 40
                    ))
                    .placed(30 - 24, 40 - 24, 48, 48)
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: 0xBE123C))
                    .placed(64, 16, 48, 48)
                RoundedRectangle(cornerRadius: 10)
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.8), .white.opacity(0)],
                        center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: 30
                    ))
                    .placed(64, 16, 48, 48)
            }
        }
    }
}
