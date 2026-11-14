import SwiftUI

/// Raw pixels: a 40 by 30 image drawn one pixel at a time, a dirty rect of it placed elsewhere, and three
/// colour swatches. The reference's putImageData ignores the transform and alpha, so pixels go straight
/// onto the tile. SwiftUI has no lab() or oklch() constructors, so those colours are converted to sRGB
/// by hand.
@MainActor
enum PixelsPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        context.fill(Paths.rect(0, 0, 150, 100), with: .color(Palette.hex(0xe2e8f0)))
        let width = 40
        let height = 30
        for y in 0..<height {
            for x in 0..<width {
                context.fill(
                    Paths.rect(Double(10 + x), Double(10 + y), 1, 1),
                    with: .color(pixelColor(x, y, width, height))
                )
            }
        }
        // The dirty rect (10, 5, 40, 18) of the same data, placed at (40, 50): only the part of it
        // inside the 40-pixel width is left.
        for y in 5..<23 {
            for x in 10..<width {
                context.fill(
                    Paths.rect(Double(40 + x - 10), Double(50 + y - 5), 1, 1),
                    with: .color(pixelColor(x, y, width, height))
                )
            }
        }
        context.fill(Paths.rect(100, 8, 40, 20), with: .color(Color(red: 0.77, green: 0.34, blue: 0)))
        context.fill(
            Paths.rect(100, 34, 40, 20),
            with: .color(Color(red: 0.25, green: 0.69, blue: 0.72).opacity(0.8))
        )
        context.fill(
            Paths.rect(100, 60, 40, 20),
            with: .color(Color(.displayP3, red: 0.2, green: 0.6, blue: 0.3))
        )
    }

    /// The reference's pixel formula: red ramps across, green down, blue is fixed, and the left half is
    /// opaque.
    private static func pixelColor(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> Color {
        Color(
            red: Double(x) / Double(width),
            green: Double(y) / Double(height),
            blue: 160.0 / 255
        ).opacity(x < width / 2 ? 1 : 0.5)
    }
}
