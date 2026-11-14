import SwiftUI

/// Two linear gradients on the same axis; the second has a middle stop.
@MainActor
enum LinearPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let red = Palette.hex(0xef4444)
        let blue = Palette.hex(0x2563eb)
        let axis = (CGPoint(x: 10, y: 0), CGPoint(x: 140, y: 0))
        context.fill(
            Paths.rect(10, 10, 130, 35),
            with: .linearGradient(
                Palette.gradient([(0, red), (1, blue)]),
                startPoint: axis.0, endPoint: axis.1
            )
        )
        // A stop added after the first fill is in the second: the gradient is rebuilt per paint.
        context.fill(
            Paths.rect(10, 55, 130, 35),
            with: .linearGradient(
                Palette.gradient([(0, red), (0.5, Palette.hex(0xfacc15)), (1, blue)]),
                startPoint: axis.0, endPoint: axis.1
            )
        )
    }
}
