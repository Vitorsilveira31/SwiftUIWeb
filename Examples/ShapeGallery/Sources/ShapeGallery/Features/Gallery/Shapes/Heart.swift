import SwiftUI

// The heart icon: a 24-unit path, scaled uniformly into the rect and centred.
struct Heart: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.minX + (rect.width - 24 * s) / 2
        let oy = rect.minY + (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        path.move(to: p(12, 21.35))
        path.addLine(to: p(10.55, 20.03))
        path.addCurve(to: p(2, 8.5), control1: p(5.4, 15.36), control2: p(2, 12.28))
        path.addCurve(to: p(7.5, 3), control1: p(2, 5.42), control2: p(4.42, 3))
        path.addCurve(to: p(12, 5.09), control1: p(9.24, 3), control2: p(10.91, 3.81))
        path.addCurve(to: p(16.5, 3), control1: p(13.09, 3.81), control2: p(14.76, 3))
        path.addCurve(to: p(22, 8.5), control1: p(19.58, 3), control2: p(22, 5.42))
        path.addCurve(to: p(13.45, 20.04), control1: p(22, 12.28), control2: p(18.6, 15.36))
        path.addLine(to: p(12, 21.35))
        path.closeSubpath()
        return path
    }
}
