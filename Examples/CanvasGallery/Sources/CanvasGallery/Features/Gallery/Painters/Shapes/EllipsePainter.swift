import SwiftUI

/// A rotated ellipse filled and half stroked, and an even-odd star whose centre is a hole.
@MainActor
enum EllipsePainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        context.fill(
            Paths.ellipse(40, 50, 30, 16, rotation: 0.5, from: 0, to: 2 * .pi),
            with: .color(Palette.hex(0x16a34a))
        )
        context.stroke(
            Paths.ellipse(40, 50, 30, 16, rotation: 0.5, from: 0, to: .pi, anticlockwise: true),
            with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2)
        )
        // Even-odd: the centre of the star is a hole.
        context.fill(
            Paths.star(110, 52, 32),
            with: .color(Palette.hex(0xe11d48)), style: FillStyle(eoFill: true)
        )
    }
}
