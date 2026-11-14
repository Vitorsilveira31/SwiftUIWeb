import SwiftUI

enum GradientStops {
    // The stops of a gradient that repeats or reflects every `period` of its vector, as SVG
    // spreadMethod does. SwiftUI gradients have no spread, so the period is written out as stops.
    static func periodic(from a: UInt32, to b: UInt32, period: CGFloat, reflect: Bool) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        var k: CGFloat = 0
        while k * period <= 1 {
            let start = min(k * period, 1)
            let end = min((k + 1) * period, 1)
            if reflect {
                let color = Int(k).isMultiple(of: 2) ? a : b
                stops.append(Gradient.Stop(color: Color(hex: color), location: start))
            } else {
                stops.append(Gradient.Stop(color: Color(hex: a), location: start))
                stops.append(Gradient.Stop(color: Color(hex: b), location: end))
            }
            k += 1
        }
        if reflect {
            stops.append(Gradient.Stop(color: Color(hex: Int(k).isMultiple(of: 2) ? a : b), location: 1))
        }
        return stops
    }
}
