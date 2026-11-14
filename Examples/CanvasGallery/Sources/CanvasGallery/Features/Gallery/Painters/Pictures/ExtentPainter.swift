import SwiftUI

/// The clip-extent operators run inside a layer, so they compose with the layer alone. SwiftUI has no
/// source-in, source-out or destination-in, so each maps to its nearest blend mode.
@MainActor
enum ExtentPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let photo = context.resolve(Image(systemName: "photo"))
        context.drawLayer { layer in
            let modes: [GraphicsContext.BlendMode] = [.sourceAtop, .clear, .destinationOut, .destinationOver, .copy]
            for (i, mode) in modes.enumerated() {
                let x = Double(i) * 30 + 1
                var cell = layer
                cell.clip(to: Paths.rect(x, 2, 28, 60))
                cell.fill(Paths.rect(x, 2, 20, 40), with: .color(Palette.hex(0x2563eb, alpha: 0.8)))
                cell.blendMode = mode
                cell.fill(Paths.circle(x + 17, 34, 11), with: .color(Palette.hex(0xef4444, alpha: 0.7)))
            }

            var strip = layer
            strip.clip(to: Paths.rect(4, 66, 142, 30))
            strip.fill(Paths.rect(0, 60, 150, 40), with: .color(Palette.hex(0x16a34a)))
            strip.blendMode = .copy
            strip.opacity = 0.6
            strip.draw(photo, in: CGRect(x: 60, y: 70, width: 30, height: 22))
        }
    }
}
