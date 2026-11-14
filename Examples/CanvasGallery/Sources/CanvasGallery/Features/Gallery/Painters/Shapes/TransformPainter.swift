import SwiftUI

/// Transforms: a rotated square, a stretched ring, a skewed square and a translated frame. Each is
/// drawn through its own copy of the context, so the transform stays with that shape only.
@MainActor
enum TransformPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        var spun = context
        spun.translateBy(x: 30, y: 30)
        spun.rotate(by: .radians(0.4))
        spun.fill(Paths.rect(-15, -10, 30, 20), with: .color(Palette.hex(0x0ea5e9)))

        // A non-uniform scale stretches the stroke too, so the ring widens with x.
        var stretched = context
        stretched.translateBy(x: 75, y: 50)
        stretched.scaleBy(x: 3, y: 1)
        stretched.stroke(
            Paths.circle(0, 0, 10), with: .color(Palette.hex(0xdc2626)), style: StrokeStyle(lineWidth: 2)
        )

        var skewed = context
        skewed.concatenate(CGAffineTransform(a: 1, b: 0.3, c: -0.4, d: 1, tx: 110, ty: 60))
        skewed.fill(Paths.rect(0, 0, 25, 25), with: .color(Palette.hex(0x84cc16)))

        // setTransform replaces the matrix rather than multiplying into it.
        var placed = context
        placed.translateBy(x: 10, y: 70)
        placed.stroke(
            Paths.rect(0, 0, 40, 20), with: .color(Palette.hex(0x7c3aed)), style: StrokeStyle(lineWidth: 4)
        )

        context.fill(Paths.rect(140, 5, 5, 5), with: .color(Palette.ink))
    }
}
