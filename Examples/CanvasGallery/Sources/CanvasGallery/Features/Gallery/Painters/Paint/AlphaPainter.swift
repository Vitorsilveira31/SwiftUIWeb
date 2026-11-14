import SwiftUI

/// Global alpha: the context's `opacity` applies to every draw made through it.
@MainActor
enum AlphaPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        var translucent = context
        translucent.opacity = 0.6
        translucent.fill(Paths.rect(15, 15, 60, 50), with: .color(Palette.hex(0xef4444)))
        translucent.fill(Paths.rect(45, 35, 60, 50), with: .color(Palette.hex(0x2563eb)))
        context.fill(Paths.circle(110, 40, 26), with: .color(Palette.hex(0x16a34a, alpha: 0.5)))
        var faint = context
        faint.opacity = 0.25
        faint.stroke(
            Paths.rect(10, 70, 130, 20), with: .color(Palette.ink), style: StrokeStyle(lineWidth: 8)
        )
    }
}
