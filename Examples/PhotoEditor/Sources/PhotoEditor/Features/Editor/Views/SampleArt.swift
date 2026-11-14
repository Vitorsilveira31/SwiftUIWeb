import SwiftUI

/// Draws the sample picture: a sky, a sun, hills and a lake.
enum SampleArt {
    static func draw(_ context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * h) }

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.30, green: 0.55, blue: 0.85), Color(red: 0.86, green: 0.93, blue: 0.99)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: h * 0.7)
            )
        )

        let sunRadius = min(w, h) * 0.08
        context.fill(
            Path(ellipseIn: CGRect(x: 0.72 * w - sunRadius, y: 0.22 * h - sunRadius, width: 2 * sunRadius, height: 2 * sunRadius)),
            with: .color(Color(red: 1, green: 0.96, blue: 0.80))
        )

        var far = Path()
        far.move(to: point(0, 0.62))
        for (x, y) in [(0.18, 0.38), (0.33, 0.55), (0.52, 0.30), (0.74, 0.52), (0.90, 0.40), (1.0, 0.55)] {
            far.addLine(to: point(x, y))
        }
        far.addLine(to: point(1, 0.75))
        far.addLine(to: point(0, 0.75))
        far.closeSubpath()
        context.fill(far, with: .color(Color(red: 0.42, green: 0.50, blue: 0.66)))

        var near = Path()
        near.move(to: point(0, 0.70))
        for (x, y) in [(0.25, 0.56), (0.50, 0.68), (0.80, 0.52), (1.0, 0.62)] {
            near.addLine(to: point(x, y))
        }
        near.addLine(to: point(1, 1))
        near.addLine(to: point(0, 1))
        near.closeSubpath()
        context.fill(near, with: .color(Color(red: 0.25, green: 0.48, blue: 0.30)))

        for (x, base) in [(0.12, 0.68), (0.20, 0.66), (0.86, 0.60), (0.93, 0.62)] {
            var tree = Path()
            tree.move(to: point(x - 0.03, base))
            tree.addLine(to: point(x, base - 0.12))
            tree.addLine(to: point(x + 0.03, base))
            tree.closeSubpath()
            context.fill(tree, with: .color(Color(red: 0.12, green: 0.32, blue: 0.20)))
        }

        context.fill(
            Path(CGRect(x: 0, y: 0.80 * h, width: w, height: 0.20 * h)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.35, green: 0.62, blue: 0.80), Color(red: 0.12, green: 0.30, blue: 0.50)]),
                startPoint: CGPoint(x: 0, y: 0.80 * h),
                endPoint: CGPoint(x: 0, y: h)
            )
        )
    }
}
