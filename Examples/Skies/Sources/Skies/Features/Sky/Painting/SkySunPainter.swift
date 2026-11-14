import SwiftUI

// The sun by day or the moon by night, with a soft halo. It sits right of the headline,
// and its arc follows the selected hour.
enum SkySunPainter {
    static func draw(_ sky: SkyInput, in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let arc = sin(min(max((sky.hour - 6) / 12, 0), 1) * Double.pi)
        let orbX = w * 0.78
        let orbY = h * SkyPalette.lerp(0.37, 0.70 - arc * 0.44, sky.day)
        let orbRadius = h * (sky.isDay ? 0.038 : 0.026)
        let orbRGB: SkyRGB = sky.isDay ? (1.0, 0.85, 0.58) : (0.72, 0.84, 1.0)
        let orbDim = 1 - sky.stormy
        let halo = h * 0.22
        let orbColor = SkyPalette.color(orbRGB)

        context.fill(
            Path(ellipseIn: CGRect(x: orbX - halo, y: orbY - halo, width: halo * 2, height: halo * 2)),
            with: .radialGradient(
                Gradient(colors: [orbColor.opacity(0.45 * orbDim), orbColor.opacity(0)]),
                center: CGPoint(x: orbX, y: orbY),
                startRadius: 0,
                endRadius: halo))
        context.fill(
            Path(ellipseIn: CGRect(x: orbX - orbRadius, y: orbY - orbRadius, width: orbRadius * 2, height: orbRadius * 2)),
            with: .color(orbColor.opacity(0.95 * orbDim)))
    }
}
