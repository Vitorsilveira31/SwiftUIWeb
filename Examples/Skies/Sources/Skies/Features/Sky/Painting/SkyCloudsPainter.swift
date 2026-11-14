import SwiftUI

// Drifting clouds: the more cover, the more of the ten banks, softly blurred.
enum SkyCloudsPainter {
    static func draw(_ sky: SkyInput, time: Double, in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let cloudCount = Int((sky.cloudCover / 100 * 10).rounded())
        guard cloudCount > 0 else { return }

        var base = SkyPalette.mix(SkyPalette.cloudNight, SkyPalette.cloudDay, sky.day)
        base = SkyPalette.mix(base, SkyPalette.dusk, sky.twilight * 0.5)
        base = SkyPalette.mix(base, (0.30, 0.34, 0.40), sky.stormy)
        let alpha = min(0.92, 0.45 + sky.cloudCover / 100 * 0.5)
        let travel = w + 320
        let cloudColor = SkyPalette.color(base)

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            for i in 0..<cloudCount {
                let seed = Double(i) * 3.7
                let speed = 5 + SkyNoise.unit(seed + 1) * 9 + sky.windSpeed * 0.05
                let x = (SkyNoise.unit(seed + 2) * travel + time * speed)
                    .truncatingRemainder(dividingBy: travel) - 160
                let y = h * (0.10 + 0.40 * SkyNoise.unit(seed + 3))
                let width = 120 + 150 * SkyNoise.unit(seed + 4)
                let height = width * 0.3
                for puff in 0..<4 {
                    let offset = Double(puff)
                    let rise = offset.truncatingRemainder(dividingBy: 2) * height * 0.25
                    layer.fill(
                        Path(ellipseIn: CGRect(x: x + width * 0.16 * offset, y: y - rise, width: width * 0.5, height: height)),
                        with: .color(cloudColor.opacity(alpha)))
                }
            }
        }
    }
}
