import SwiftUI

/// Radial gradients: a teal halo, an orange ball and the halo as a stroke.
/// Canvas gives each radial gradient its own start and end circle; SwiftUI takes one centre, so the
/// ball's gradient is centred on its own circle and the halo keeps the first centre.
@MainActor
enum RadialPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let halo = GraphicsContext.Shading.radialGradient(
            Palette.gradient([
                (0, .white), (0.6, Palette.hsl(160, 0.8, 0.4)), (1, .clear),
            ]),
            center: CGPoint(x: 40, y: 50), startRadius: 4, endRadius: 36
        )
        context.fill(Paths.rect(0, 0, 80, 100), with: halo)
        let ball = GraphicsContext.Shading.radialGradient(
            Palette.gradient([(0, Palette.hex(0xf97316)), (1, Palette.hex(0x7c2d12))]),
            center: CGPoint(x: 115, y: 55), startRadius: 5, endRadius: 30
        )
        context.fill(Paths.circle(115, 55, 30), with: ball)
        context.stroke(Paths.rect(85, 8, 55, 12), with: halo, style: StrokeStyle(lineWidth: 6))
    }
}
