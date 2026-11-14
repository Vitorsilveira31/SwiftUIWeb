import SwiftUI

/// A 40 by 25 pixel grid drawn in its own units under a scale, with a blur filter for the smoothing
/// the reference gets from stretching its bitmap.
@MainActor
enum BitmapPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        var pixels = context
        pixels.scaleBy(x: TileMetrics.width / 40, y: TileMetrics.height / 25)
        pixels.addFilter(.blur(radius: 1))
        pixels.fill(Paths.rect(0, 0, 40, 25), with: .color(Palette.hex(0xe2e8f0)))
        for y in 0..<5 {
            for x in 0..<8 where (x + y) % 2 == 1 {
                pixels.fill(
                    Paths.rect(Double(x * 5), Double(y * 5), 5, 5), with: .color(Palette.ink)
                )
            }
        }
        pixels.stroke(
            Paths.polyline([(0, 25), (40, 0)]),
            with: .color(Palette.hex(0xdc2626)), style: StrokeStyle(lineWidth: 1)
        )
    }
}
