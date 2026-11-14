import SwiftUI

// A quadratic arc from the bottom left to the bottom right, peaking in the middle.
struct SunArc: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.3))
        }
    }

    // The point the same curve reaches at `progress` (0 at sunrise, 1 at sunset).
    static func point(at progress: Double, in size: CGSize) -> CGPoint {
        let t = progress
        let start = CGPoint(x: 0, y: size.height)
        let control = CGPoint(x: size.width / 2, y: -size.height * 0.3)
        let end = CGPoint(x: size.width, y: size.height)
        return CGPoint(
            x: (1 - t) * (1 - t) * start.x + 2 * (1 - t) * t * control.x + t * t * end.x,
            y: (1 - t) * (1 - t) * start.y + 2 * (1 - t) * t * control.y + t * t * end.y)
    }
}
