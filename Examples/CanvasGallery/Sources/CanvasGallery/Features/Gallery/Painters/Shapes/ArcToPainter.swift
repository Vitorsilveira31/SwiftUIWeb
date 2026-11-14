import SwiftUI

/// Tangent arcs: a rounded corner pair, a collinear case and a zero-radius case, then an orphan line.
@MainActor
enum ArcToPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        // SwiftUI's tangent arcs cover the collinear and zero-radius cases in the same call.
        var rounded = Path()
        rounded.move(to: CGPoint(x: 10, y: 90))
        rounded.addArc(tangent1End: CGPoint(x: 10, y: 10), tangent2End: CGPoint(x: 70, y: 10), radius: 20)
        rounded.addArc(tangent1End: CGPoint(x: 70, y: 10), tangent2End: CGPoint(x: 70, y: 90), radius: 30)
        rounded.addLine(to: CGPoint(x: 70, y: 90))
        context.stroke(rounded, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3))

        var collinear = Path()
        collinear.move(to: CGPoint(x: 85, y: 20))
        collinear.addArc(tangent1End: CGPoint(x: 110, y: 20), tangent2End: CGPoint(x: 140, y: 20), radius: 15)
        collinear.addLine(to: CGPoint(x: 140, y: 45))
        context.stroke(collinear, with: .color(Palette.hex(0x2563eb)), style: StrokeStyle(lineWidth: 3))

        var zeroRadius = Path()
        zeroRadius.move(to: CGPoint(x: 85, y: 60))
        zeroRadius.addArc(tangent1End: CGPoint(x: 140, y: 60), tangent2End: CGPoint(x: 140, y: 90), radius: 0)
        zeroRadius.addLine(to: CGPoint(x: 140, y: 90))
        context.stroke(zeroRadius, with: .color(Palette.hex(0x2563eb)), style: StrokeStyle(lineWidth: 3))

        // With no subpath, arcTo starts one at its first point, so only the line is left.
        var orphan = Path()
        orphan.move(to: CGPoint(x: 100, y: 80))
        orphan.addLine(to: CGPoint(x: 110, y: 95))
        context.fill(orphan, with: .color(Palette.hex(0x16a34a)))
    }
}
