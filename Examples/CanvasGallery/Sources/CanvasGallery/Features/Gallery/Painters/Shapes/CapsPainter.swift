import SwiftUI

/// Line caps (butt, round, square), line joins (miter, round, bevel) and a miter limit.
@MainActor
enum CapsPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let ink = Palette.ink
        let lineCaps: [CGLineCap] = [.butt, .round, .square]
        for (i, cap) in lineCaps.enumerated() {
            let y = 15 + Double(i) * 18
            context.stroke(
                Paths.polyline([(15, y), (60, y)]),
                with: .color(ink), style: StrokeStyle(lineWidth: 10, lineCap: cap)
            )
        }
        let violet = Palette.hex(0x7c3aed)
        let lineJoins: [CGLineJoin] = [.miter, .round, .bevel]
        for (i, join) in lineJoins.enumerated() {
            let x = 80 + Double(i) * 22
            context.stroke(
                Paths.polyline([(x, 85), (x + 10, 20), (x + 20, 85)]),
                with: .color(violet), style: StrokeStyle(lineWidth: 8, lineJoin: join)
            )
        }
        // The miter limit makes this sharp join fall back to a bevel.
        context.stroke(
            Paths.polyline([(10, 90), (30, 70), (50, 90)]),
            with: .color(Palette.hex(0xf97316)),
            style: StrokeStyle(lineWidth: 6, lineJoin: .miter, miterLimit: 1.5)
        )
    }
}
