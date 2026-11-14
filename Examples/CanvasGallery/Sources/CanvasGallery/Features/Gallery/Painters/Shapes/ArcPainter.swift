import SwiftUI

/// Arcs: a clockwise half circle that bulges down, an anticlockwise one that bulges up, two rings and a wedge.
@MainActor
enum ArcPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let ink = Palette.ink
        // A clockwise arc from 0 to pi bulges down; anticlockwise bulges up.
        context.fill(Paths.arc(40, 50, 28, 0, .pi), with: .color(Palette.hex(0xef4444)))
        context.fill(
            Paths.arc(110, 50, 28, 0, .pi, anticlockwise: true),
            with: .color(Palette.hex(0x2563eb))
        )
        context.stroke(Paths.arc(75, 50, 40, -.pi / 2, 0), with: .color(ink), style: StrokeStyle(lineWidth: 3))
        context.stroke(
            Paths.arc(75, 50, 12, 0, 2 * .pi, anticlockwise: true),
            with: .color(ink), style: StrokeStyle(lineWidth: 3)
        )
        var wedge = Path()
        wedge.move(to: CGPoint(x: 75, y: 85))
        wedge.addArc(
            center: CGPoint(x: 75, y: 85), radius: 12,
            startAngle: .radians(.pi), endAngle: .radians(1.5 * .pi), clockwise: true
        )
        wedge.closeSubpath()
        context.fill(wedge, with: .color(Palette.hex(0x16a34a)))
    }
}
