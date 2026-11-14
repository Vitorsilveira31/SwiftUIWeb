import SwiftUI

/// Five text alignments drawn from a guide line at x = 75: start, end, left, right and centre.
@MainActor
enum TextAlignPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        context.stroke(
            Paths.polyline([(75.5, 0), (75.5, 100)]),
            with: .color(Palette.hex(0x94a3b8)), style: StrokeStyle(lineWidth: 1)
        )
        let rows: [(String, Double)] = [("start", 0), ("end", 1), ("left", 0), ("right", 1), ("center", 0.5)]
        for (i, row) in rows.enumerated() {
            CanvasText.draw(
                &context, row.0, font: .system(size: 15), color: Palette.ink,
                at: CGPoint(x: 75, y: 16 + Double(i) * 19),
                anchor: UnitPoint(x: row.1, y: CanvasText.baselineAnchor)
            )
        }
    }
}
