import SwiftUI

// Stars, only at night and at twilight, each with its own slow twinkle.
enum SkyStarsPainter {
    static func draw(_ sky: SkyInput, time: Double, in context: inout GraphicsContext, size: CGSize) {
        guard !sky.isDay || sky.twilight > 0.05 else { return }
        let w = size.width
        let h = size.height
        let visibility = (1 - sky.day) * (1 - sky.twilight * 0.8)

        for i in 0..<90 {
            let seed = Double(i)
            let x = SkyNoise.unit(seed * 1.31 + 0.7) * w
            let y = SkyNoise.unit(seed * 2.17 + 3.3) * h * 0.6
            let radius = 0.6 + SkyNoise.unit(seed * 5.9) * 1.2
            let twinkle = 0.5 + 0.5 * sin(time * 0.7 + seed * 1.7)
            let alpha = (0.35 + 0.65 * twinkle) * visibility
            guard alpha > 0.02 else { continue }
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(Color(red: 0.70, green: 0.81, blue: 1.0).opacity(alpha)))
        }
    }
}
