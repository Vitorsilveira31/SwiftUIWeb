import SwiftUI

/// Dashed strokes with three patterns and a dash phase, then a dashed circle and a solid rectangle.
@MainActor
enum DashPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let ink = Palette.ink
        context.stroke(
            Paths.polyline([(10, 15), (140, 15)]),
            with: .color(ink), style: StrokeStyle(lineWidth: 3, dash: [10, 5])
        )
        context.stroke(
            Paths.polyline([(10, 35), (140, 35)]),
            with: .color(ink), style: StrokeStyle(lineWidth: 3, dash: [8, 4, 2])
        )
        context.stroke(
            Paths.polyline([(10, 55), (140, 55)]),
            with: .color(ink), style: StrokeStyle(lineWidth: 3, dash: [8, 4, 2], dashPhase: 6)
        )
        let red = Palette.hex(0xdc2626)
        context.stroke(
            Paths.circle(75, 78, 16), with: .color(red), style: StrokeStyle(lineWidth: 4, dash: [12, 6])
        )
        context.stroke(Paths.rect(110, 65, 30, 25), with: .color(red), style: StrokeStyle(lineWidth: 4))
    }
}
