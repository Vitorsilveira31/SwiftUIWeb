import SwiftUI

// A horizontal sunrise on the rounded rect, and a radial glow with its focal point
// at 30% (SwiftUI's centre) that also strokes with the sunrise.
struct FxGradients: View {
    private static let sunrise: [Gradient.Stop] = [
        Gradient.Stop(color: Color(hex: 0xF59E0B), location: 0),
        Gradient.Stop(color: Color(hex: 0xEF4444), location: 0.5),
        Gradient.Stop(color: Color(hex: 0x7C3AED), location: 1),
    ]

    var body: some View {
        FixtureTile(name: "fx-gradients") {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(stops: Self.sunrise, startPoint: .leading, endPoint: .trailing))
                    .placed(6, 8, 56, 64)
                Circle()
                    .fill(RadialGradient(
                        stops: [
                            Gradient.Stop(color: .white, location: 0),
                            Gradient.Stop(color: Color(hex: 0x0EA5E9), location: 1),
                        ],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 2,
                        endRadius: 26
                    ))
                    .overlay(
                        Circle().stroke(
                            LinearGradient(stops: Self.sunrise, startPoint: .leading, endPoint: .trailing),
                            lineWidth: 4
                        )
                    )
                    .placed(90 - 26, 40 - 26, 52, 52)
            }
        }
    }
}
