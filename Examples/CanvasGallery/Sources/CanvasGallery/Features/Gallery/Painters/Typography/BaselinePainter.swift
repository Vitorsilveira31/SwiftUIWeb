import SwiftUI

/// Six baseline positions, each a vertical anchor on the text box, against a red guide line.
/// SwiftUI has no baseline modes, so each one becomes a vertical anchor.
@MainActor
enum BaselinePainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        context.stroke(
            Paths.polyline([(0, 50.5), (150, 50.5)]),
            with: .color(Palette.hex(0xef4444)), style: StrokeStyle(lineWidth: 1)
        )
        let baselines: [Double] = [0, 0.15, 0.5, 0.8, 0.95, 1]
        for (i, y) in baselines.enumerated() {
            CanvasText.draw(
                &context, "Ág", font: .system(size: 18, weight: .bold), color: Palette.hex(0x1e293b),
                at: CGPoint(x: 2 + Double(i) * 25, y: 50), anchor: UnitPoint(x: 0, y: y)
            )
        }
    }
}
