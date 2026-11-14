import Foundation
import SwiftUI

/// Path builders shared by the fixtures. Each mirrors the Canvas 2D call it stands for and takes
/// Double coordinates, since the painters compute them in Double.
enum Paths {
    static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
        Path(ellipseIn: frame(cx - r, cy - r, 2 * r, 2 * r))
    }

    static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Path {
        Path(frame(x, y, width, height))
    }

    static func polyline(_ points: [(Double, Double)]) -> Path {
        var path = Path()
        for (index, xy) in points.enumerated() {
            let p = at(xy.0, xy.1)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    /// Canvas `arc()`. The default (clockwise) runs the angles upwards in canvas space, which is
    /// SwiftUI's `clockwise: true`, so the direction matches the reference.
    static func arc(
        _ cx: Double, _ cy: Double, _ r: Double, _ from: Double, _ to: Double, anticlockwise: Bool = false
    ) -> Path {
        var path = Path()
        path.addArc(
            center: at(cx, cy), radius: CGFloat(r),
            startAngle: .radians(from), endAngle: .radians(to), clockwise: !anticlockwise
        )
        return path
    }

    /// Canvas `ellipse()` as a polyline, since SwiftUI has no rotated elliptical arc.
    static func ellipse(
        _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, rotation: Double,
        from: Double, to: Double, anticlockwise: Bool = false
    ) -> Path {
        let sweep = anticlockwise ? -(to - from) : to - from
        let steps = 96
        var path = Path()
        for i in 0...steps {
            let t = from + sweep * Double(i) / Double(steps)
            let x = rx * cos(t)
            let y = ry * sin(t)
            let p = at(
                cx + x * cos(rotation) - y * sin(rotation),
                cy + x * sin(rotation) + y * cos(rotation)
            )
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    /// The five-point star of the ellipse and clip fixtures.
    static func star(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
        var path = Path()
        for i in 0..<5 {
            let a = -Double.pi / 2 + Double(i) * 4 * Double.pi / 5
            let p = at(cx + r * cos(a), cy + r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    private static func at(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}
