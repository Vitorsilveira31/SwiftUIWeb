import SwiftUI

/// Clearing is a fill with the `.clear` blend mode: it erases to transparency, so the backdrop shows
/// through, which is what the Backdrop toggle relies on.
@MainActor
enum ClearPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        context.fill(Paths.rect(0, 0, 150, 100), with: .color(Palette.hex(0x1e293b)))

        var turned = context
        turned.translateBy(x: 45, y: 50)
        turned.rotate(by: .radians(0.5))
        turned.blendMode = .clear
        turned.fill(Paths.rect(-20, -12, 40, 24), with: .color(.black))

        var round = context
        round.clip(to: Paths.circle(110, 50, 25))
        round.blendMode = .clear
        round.fill(Paths.rect(90, 20, 60, 30), with: .color(.black))
    }
}
