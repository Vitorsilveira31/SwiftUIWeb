import SwiftUI

// Hatching: bars of `barWidth` every `period`, in a pattern rotated by `angle`
// degrees about the picture's origin.
struct Hatching: Shape {
    let angle: Double
    let barWidth: CGFloat
    let period: CGFloat

    func path(in rect: CGRect) -> Path {
        var bars = Path()
        var k: CGFloat = -40
        while k * period < 200 {
            bars.addRect(CGRect(x: k * period, y: -200, width: barWidth, height: 600))
            k += 1
        }
        let turn = CGAffineTransform(rotationAngle: CGFloat(angle) * .pi / 180)
        return bars.applying(turn)
    }
}
