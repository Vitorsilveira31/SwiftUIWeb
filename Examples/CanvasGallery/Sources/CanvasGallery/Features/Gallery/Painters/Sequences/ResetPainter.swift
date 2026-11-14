import SwiftUI

/// A clip, a clear and a reset. The green fill and clip of step 0 bound step 1's clear. Step 2's
/// reset drops the clip and starts again from a blue rect, so the replay starts there.
@MainActor
enum ResetPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let start = step >= 2 ? 2 : 0
        var working = context
        for s in start...step {
            switch s {
            case 0:
                working.fill(Paths.rect(0, 0, 150, 100), with: .color(Palette.hex(0x16a34a)))
                working.clip(to: Paths.rect(0, 0, 75, 100))
            case 1:
                var clearing = working
                clearing.blendMode = .clear
                clearing.fill(Paths.rect(0, 0, 150, 100), with: .color(.black))
            case 2:
                working = context
                working.fill(Paths.rect(20, 20, 110, 60), with: .color(Palette.hex(0x2563eb)))
            default:
                var clearing = working
                clearing.blendMode = .clear
                clearing.fill(Paths.rect(0, 0, 60, 60), with: .color(.black))
            }
        }
    }
}
