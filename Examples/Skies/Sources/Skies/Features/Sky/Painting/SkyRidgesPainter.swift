import SwiftUI

// Two low rolling ridges, stationary, anchoring the moving sky.
enum SkyRidgesPainter {
    static func draw(_ sky: SkyInput, in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        var ridge = Path()
        ridge.move(to: CGPoint(x: 0, y: h))
        for x in stride(from: 0.0, through: w, by: 6.0) {
            let u = x / w
            let y = h * 0.90 + sin(u * 7 + 0.4) * h * 0.025 + sin(u * 13 + 2.0) * h * 0.012
            ridge.addLine(to: CGPoint(x: x, y: y))
        }
        ridge.addLine(to: CGPoint(x: w, y: h))
        ridge.closeSubpath()

        let hill = SkyPalette.mix(SkyPalette.hillNight, SkyPalette.hillDay, sky.day)
        context.fill(ridge, with: .color(SkyPalette.color(hill)))
    }
}
