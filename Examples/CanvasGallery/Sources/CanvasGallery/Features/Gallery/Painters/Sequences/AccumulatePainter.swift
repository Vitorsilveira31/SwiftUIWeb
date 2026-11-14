import SwiftUI

/// Each step adds a dot. Canvas keeps the bitmap between draws, but a SwiftUI canvas starts blank on
/// every redraw, so the dots of steps 0...step are drawn again each time.
@MainActor
enum AccumulatePainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        for s in 0...step {
            context.fill(
                Paths.circle(20 + Double(s) * 28, 50, 11),
                with: .color(Palette.hsl(Double(s) * 60, 0.7, 0.45))
            )
        }
    }
}
