import SwiftUI

/// A measured box around each run, the way the reference strokes its actualBoundingBox.
@MainActor
enum TextMeasurePainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        measuredText(
            &context, "Measure", font: .system(size: 26), at: CGPoint(x: 8, y: 36),
            anchor: UnitPoint(x: 0, y: CanvasText.baselineAnchor)
        )
        measuredText(
            &context, "jumpy", font: .system(size: 20, weight: .bold), at: CGPoint(x: 75, y: 60),
            anchor: UnitPoint(x: 0.5, y: 0)
        )
    }

    /// Draws `string` and a red box around its measured size, anchored like the text.
    private static func measuredText(
        _ context: inout GraphicsContext, _ string: String, font: Font, at point: CGPoint, anchor: UnitPoint
    ) {
        var resolved = context.resolve(Text(string).font(font))
        resolved.shading = .color(Palette.ink)
        let size = resolved.measure(in: CanvasText.unbounded)
        let origin = CGPoint(x: point.x - anchor.x * size.width, y: point.y - anchor.y * size.height)
        context.stroke(
            Path(CGRect(origin: origin, size: size)),
            with: .color(Palette.hex(0xef4444)), style: StrokeStyle(lineWidth: 1)
        )
        context.fill(
            Paths.rect(origin.x, origin.y + size.height + 2, size.width, 2),
            with: .color(Palette.ink)
        )
        context.draw(resolved, at: point, anchor: anchor)
    }
}
