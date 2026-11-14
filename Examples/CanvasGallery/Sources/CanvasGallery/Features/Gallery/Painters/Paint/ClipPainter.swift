import SwiftUI

/// Two star clips: one with the default rule, one even-odd. A square outside both shows the clips end.
@MainActor
enum ClipPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        var left = context
        left.clip(to: Paths.star(38, 52, 34))
        left.fill(Paths.rect(0, 0, 75, 100), with: .color(Palette.hex(0x0ea5e9)))

        var right = context
        right.clip(to: Paths.star(112, 52, 34), style: FillStyle(eoFill: true))
        right.fill(Paths.rect(75, 0, 75, 100), with: .color(Palette.hex(0xf43f5e)))

        // Outside both clips again.
        context.fill(Paths.rect(70, 45, 10, 10), with: .color(Palette.ink))
    }
}
