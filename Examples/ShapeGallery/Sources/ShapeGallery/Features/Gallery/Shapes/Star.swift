import SwiftUI

// An icon path written in a 24 x 24 view box, drawn into whatever rect it is given.
struct Star: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (12, 2), (15.09, 8.26), (22, 9.27), (17, 14.14), (18.18, 21.02),
            (12, 17.77), (5.82, 21.02), (7, 14.14), (2, 9.27), (8.91, 8.26),
        ]
        let sx = rect.width / 24
        let sy = rect.height / 24
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + point.0 * sx, y: rect.minY + point.1 * sy)
            if index == 0 {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
        }
        path.closeSubpath()
        return path
    }
}
