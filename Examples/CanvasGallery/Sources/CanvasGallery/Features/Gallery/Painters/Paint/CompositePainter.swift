import SwiftUI

/// The blend modes, one per cell of a 7 by 3 grid. Each cell clips to its own box, so an operator
/// only reaches what that cell painted.
@MainActor
enum CompositePainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let modes: [GraphicsContext.BlendMode] = [
            .normal, .sourceAtop, .destinationOver, .destinationOut, .xor, .plusLighter, .multiply,
            .screen, .overlay, .darken, .lighten, .colorDodge, .colorBurn, .hardLight, .softLight,
            .difference, .exclusion, .hue, .saturation, .color, .luminosity,
        ]
        for (i, mode) in modes.enumerated() {
            let x = Double(i % 7) * 21 + 2
            let y = Double(i / 7) * 33 + 2
            var cell = context
            cell.clip(to: Paths.rect(x, y, 20, 32))
            cell.fill(Paths.rect(x, y, 14, 22), with: .color(Palette.hex(0x2563eb, alpha: 0.7)))
            cell.blendMode = mode
            cell.fill(Paths.circle(x + 13, y + 20, 9), with: .color(Palette.hex(0xef4444, alpha: 0.8)))
        }
    }
}
