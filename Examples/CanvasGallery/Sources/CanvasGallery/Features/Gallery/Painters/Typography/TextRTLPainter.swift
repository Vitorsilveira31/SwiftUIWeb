import SwiftUI

/// Right-to-left runs, a blue run and a run in the tile's foreground colour.
@MainActor
enum TextRTLPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        // A right-to-left mark starts the run in right-to-left order: SwiftUI does not expose the
        // canvas direction, so the mark stands in for it.
        let rlm = "\u{200F}"
        let font = Font.system(size: 16)
        let ink = Palette.ink
        let baseline = CanvasText.baselineAnchor
        CanvasText.draw(
            &context, rlm + "Hello, world!", font: font, color: ink,
            at: CGPoint(x: 144, y: 22), anchor: UnitPoint(x: 1, y: baseline)
        )
        CanvasText.draw(
            &context, rlm + "(end) 42", font: font, color: ink,
            at: CGPoint(x: 144, y: 46), anchor: UnitPoint(x: 0, y: baseline)
        )
        CanvasText.draw(
            &context, "Hello, world!", font: font, color: Palette.hex(0x2563eb),
            at: CGPoint(x: 6, y: 72), anchor: UnitPoint(x: 0, y: baseline)
        )
        // No explicit colour: the run takes the tile's foreground, the reference's currentColor.
        let current = context.resolve(Text("current colour").font(font))
        context.draw(current, at: CGPoint(x: 6, y: 94), anchor: UnitPoint(x: 0, y: baseline))
    }
}
