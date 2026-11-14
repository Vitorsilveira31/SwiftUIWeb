import SwiftUI

/// Patterns: a grid of tiles in a clip, a row of tiles along the top, and a plain thick stroke.
/// SwiftUI has no pattern shading, so each pattern is its tile repeated on a grid inside the clip.
@MainActor
enum PatternPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let tile = context.resolve(Image(systemName: "photo"))
        var repeated = context
        repeated.clip(to: Paths.rect(0, 0, 70, 100))
        for row in 0..<5 {
            for column in 0..<4 {
                repeated.draw(
                    tile, in: CGRect(x: Double(column) * 20, y: Double(row) * 22, width: 16, height: 16)
                )
            }
        }

        // repeat-x at half scale: a row of tiles along the top of its box.
        var horizontal = context
        horizontal.clip(to: Paths.rect(75, 0, 75, 60))
        for column in 0..<4 {
            horizontal.draw(tile, in: CGRect(x: 75 + Double(column) * 20, y: 10, width: 16, height: 16))
        }

        // The no-repeat stroke is drawn as a plain stroke.
        context.stroke(
            Paths.rect(84, 66, 50, 26),
            with: .color(Palette.hex(0x64748b)), style: StrokeStyle(lineWidth: 12)
        )
    }
}
