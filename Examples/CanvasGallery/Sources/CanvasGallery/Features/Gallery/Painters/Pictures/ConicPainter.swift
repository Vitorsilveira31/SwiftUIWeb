import SwiftUI

/// Two conic gradients, each centred on its reference point: the colour wheel on the disc, the grey
/// sweep on the box.
@MainActor
enum ConicPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let wheel = Palette.gradient([
            (0, Palette.hex(0xef4444)), (0.25, Palette.hex(0xf59e0b)),
            (0.5, Palette.hex(0x16a34a)), (0.75, Palette.hex(0x2563eb)),
            (1, Palette.hex(0xef4444)),
        ])
        context.fill(
            Paths.circle(40, 50, 36),
            with: .conicGradient(wheel, center: CGPoint(x: 40, y: 50), angle: .radians(-.pi / 2))
        )
        let dark = Palette.gradient([
            (0, Palette.ink), (0.5, Palette.hex(0xe2e8f0)), (1, Palette.ink),
        ])
        context.fill(
            Paths.rect(80, 20, 60, 60),
            with: .conicGradient(dark, center: CGPoint(x: 110, y: 50), angle: .radians(0.8))
        )
    }
}
