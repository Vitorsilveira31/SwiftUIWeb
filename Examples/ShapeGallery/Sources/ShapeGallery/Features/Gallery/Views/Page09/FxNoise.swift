import SwiftUI

// Noise, a wave of the picture, and an emboss; drawn as noise and a plain shape.
struct FxNoise: View {
    var body: some View {
        FixtureTile(name: "fx-noise") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.white)
                    .placed(4, 4, 36, 72)
                FilmGrain()
                    .placed(4, 4, 36, 72)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: 0x0891B2))
                    .placed(48, 14, 28, 52)
                Circle()
                    .fill(Color(hex: 0xF59E0B))
                    .placed(82, 24, 32, 32)
                    .overlay(Circle().stroke(Color(hex: 0xFFFFFF, opacity: 0.7), lineWidth: 1).offset(x: -1, y: -1))
            }
        }
    }
}
