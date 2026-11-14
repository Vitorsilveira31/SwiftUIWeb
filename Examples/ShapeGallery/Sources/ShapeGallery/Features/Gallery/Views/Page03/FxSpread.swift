import SwiftUI

// Three bands: reflected, repeated, and a gradient turned 45 degrees. The turned band is an
// approximation of the 45-degree repeat; SwiftUI has no spread method, so see GradientStops.
struct FxSpread: View {
    var body: some View {
        FixtureTile(name: "fx-spread") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(LinearGradient(
                        stops: GradientStops.periodic(from: 0x0F766E, to: 0x99F6E4, period: 0.25, reflect: true),
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .placed(4, 4, 112, 22)
                Rectangle()
                    .fill(LinearGradient(
                        stops: GradientStops.periodic(from: 0x1D4ED8, to: 0xBFDBFE, period: 0.2, reflect: false),
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .placed(4, 30, 112, 20)
                Rectangle()
                    .fill(LinearGradient(
                        stops: Self.hardStripes(from: 0xBE123C, to: 0xFDA4AF, period: 0.18),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .placed(4, 54, 112, 22)
            }
        }
    }

    // Stripes that switch colour half way through each period.
    private static func hardStripes(from a: UInt32, to b: UInt32, period: CGFloat) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        var k: CGFloat = 0
        while k * period <= 1 {
            let start = min(k * period, 1)
            let middle = min((k + 0.5) * period, 1)
            let end = min((k + 1) * period, 1)
            stops.append(Gradient.Stop(color: Color(hex: a), location: start))
            stops.append(Gradient.Stop(color: Color(hex: a), location: middle))
            stops.append(Gradient.Stop(color: Color(hex: b), location: middle))
            stops.append(Gradient.Stop(color: Color(hex: b), location: end))
            k += 1
        }
        return stops
    }
}
