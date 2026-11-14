import SwiftUI

/// Each step draws an amber square; even steps add a red one below, odd steps add a dark one.
/// The reference throws after the dark square on odd steps, so its red square is never drawn. SwiftUI
/// has no exceptions here: the odd step simply stops after the dark square.
@MainActor
enum ThrowingPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        for s in 0...step {
            let x = Double(10 + s * 20)
            context.fill(Paths.rect(x, 10, 18, 18), with: .color(Palette.hex(0xf59e0b)))
            if s % 2 == 1 {
                context.fill(Paths.rect(x, 40, 18, 18), with: .color(Palette.ink))
                continue
            }
            context.fill(Paths.rect(x, 70, 18, 18), with: .color(Palette.hex(0xdc2626)))
        }
    }
}
