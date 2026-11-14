import SwiftUI

/// Shadows as filters: a soft shadow on a sky box, a scaled ring, a hard-shadowed label and a picture.
/// The reference's shadow ignores the transform; here the filter is applied before it, so the scaled
/// ring gets its shadow scaled too.
@MainActor
enum ShadowPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        var sky = context
        sky.addFilter(.shadow(color: Palette.hex(0x0f172a, alpha: 0.6), radius: 6, x: 4, y: 5))
        sky.fill(Paths.rect(10, 10, 50, 34), with: .color(Palette.hex(0x38bdf8)))

        var ring = sky
        ring.translateBy(x: 100, y: 30)
        ring.scaleBy(x: 2, y: 2)
        ring.rotate(by: .radians(0.3))
        ring.stroke(
            Paths.circle(0, 0, 9),
            with: .color(Palette.hex(0xf97316)), style: StrokeStyle(lineWidth: 3)
        )

        var label = context
        label.addFilter(.shadow(color: Palette.hex(0xdc2626), radius: 0, x: 3, y: -3))
        CanvasText.draw(
            &label, "Shadow", font: .system(size: 20, weight: .bold), color: Palette.ink,
            at: CGPoint(x: 10, y: 80), anchor: UnitPoint(x: 0, y: CanvasText.baselineAnchor)
        )

        var picture = context
        picture.addFilter(.shadow(color: Palette.hex(0xdc2626), radius: 3, x: 3, y: -3))
        picture.draw(
            context.resolve(Image(systemName: "photo")),
            in: CGRect(x: 100, y: 62, width: 40, height: 30)
        )
    }
}
