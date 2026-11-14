import SwiftUI

/// Path2D: a heart from two half-circle arcs and two quadratic curves, a ring, a transformed copy and a
/// clip. The current path survives the fills, as in the reference.
@MainActor
enum Path2DPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        var heart = Path()
        heart.move(to: CGPoint(x: 30, y: 25))
        heart.addArc(
            center: CGPoint(x: 40, y: 25), radius: 10,
            startAngle: .radians(.pi), endAngle: .radians(2 * .pi), clockwise: true
        )
        heart.addArc(
            center: CGPoint(x: 60, y: 25), radius: 10,
            startAngle: .radians(.pi), endAngle: .radians(2 * .pi), clockwise: true
        )
        heart.addQuadCurve(to: CGPoint(x: 50, y: 60), control: CGPoint(x: 70, y: 45))
        heart.addQuadCurve(to: CGPoint(x: 30, y: 25), control: CGPoint(x: 30, y: 45))
        heart.closeSubpath()
        context.fill(heart, with: .color(Palette.hex(0xe11d48)))

        var ring = Path()
        ring.addEllipse(in: CGRect(x: 80, y: 20, width: 60, height: 60))
        ring.addEllipse(in: CGRect(x: 95, y: 35, width: 30, height: 30))
        context.fill(ring, with: .color(Palette.hex(0x0ea5e9)), style: FillStyle(eoFill: true))

        let both = heart.applying(CGAffineTransform(a: 0.6, b: 0, c: 0, d: 0.6, tx: -10, ty: 55))
        context.stroke(both, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2))

        var clipped = context
        clipped.clip(to: ring, style: FillStyle(eoFill: true))
        clipped.fill(Paths.rect(80, 40, 70, 20), with: .color(Palette.hex(0xfacc15, alpha: 0.8)))

        // The rect is the current path; filling the heart leaves it, and the fill after is the rect's.
        context.fill(heart, with: .color(Palette.hex(0x0ea5e9)))
        context.fill(Paths.rect(2, 2, 10, 10), with: .color(Palette.hex(0x16a34a)))
    }
}
