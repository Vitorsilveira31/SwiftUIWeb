import SwiftUI

/// Rounded rectangles: one radius, per-corner radii, a stroked shape and an oversized radius.
/// SwiftUI takes one radius per shape; per-corner radii use `UnevenRoundedRectangle`.
@MainActor
enum RoundRectPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        context.fill(
            Path(roundedRect: CGRect(x: 8, y: 8, width: 60, height: 38), cornerRadius: 10),
            with: .color(Palette.hex(0x0ea5e9))
        )
        let perCorner = UnevenRoundedRectangle(
            topLeadingRadius: 2, bottomLeadingRadius: 26, bottomTrailingRadius: 18, topTrailingRadius: 10
        )
        context.fill(
            perCorner.path(in: CGRect(x: 80, y: 8, width: 62, height: 38)),
            with: .color(Palette.hex(0xa855f7))
        )
        context.fill(
            Path(roundedRect: CGRect(x: 8, y: 54, width: 60, height: 38), cornerRadius: 8),
            with: .color(Palette.hex(0xf59e0b))
        )
        // A negative width is normalised by the reference; here the rect is written positively.
        let stroked = UnevenRoundedRectangle(
            topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 4, topTrailingRadius: 16
        )
        context.stroke(
            stroked.path(in: CGRect(x: 80, y: 54, width: 62, height: 38)),
            with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3)
        )
        // The reference scales an oversized radius down to half the box side.
        context.fill(
            Path(roundedRect: CGRect(x: 100, y: 62, width: 20, height: 20), cornerRadius: 10),
            with: .color(Palette.hex(0xef4444))
        )
    }
}
