import SwiftUI

/// The current path outlives fill and clear: the same triangle is stroked after the clear, and the
/// next rect is added to it, so the last fill covers both shapes.
@MainActor
enum KeptPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        var triangle = Path()
        triangle.move(to: CGPoint(x: 20, y: 80))
        triangle.addLine(to: CGPoint(x: 60, y: 15))
        triangle.addLine(to: CGPoint(x: 100, y: 80))
        triangle.closeSubpath()
        context.fill(triangle, with: .color(Palette.hex(0xfde047)))

        var cleared = context
        cleared.blendMode = .clear
        cleared.fill(Paths.rect(50, 50, 20, 20), with: .color(.black))

        context.stroke(triangle, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 4))

        var both = triangle
        both.addRect(CGRect(x: 110, y: 20, width: 30, height: 60))
        context.fill(both, with: .color(Palette.hex(0x2563eb, alpha: 0.5)))
    }
}
