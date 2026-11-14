import SwiftUI

// Colour matrices on a gradient: saturate, hue rotation, and luminance to alpha
// (the last approximated by grayscale, since SwiftUI has no matrix filter).
struct FxMatrix: View {
    private let rainbow = LinearGradient(
        stops: [
            Gradient.Stop(color: Color(hex: 0xEF4444), location: 0),
            Gradient.Stop(color: Color(hex: 0x22C55E), location: 0.5),
            Gradient.Stop(color: Color(hex: 0x3B82F6), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        FixtureTile(name: "fx-matrix") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(rainbow)
                    .placed(6, 6, 108, 20)
                    .saturation(0.2)
                Rectangle()
                    .fill(rainbow)
                    .placed(6, 30, 108, 20)
                    .hueRotation(.degrees(120))
                Rectangle()
                    .fill(rainbow)
                    .placed(6, 54, 108, 20)
                    .grayscale(1)
                    .brightness(-0.2)
            }
        }
    }
}
