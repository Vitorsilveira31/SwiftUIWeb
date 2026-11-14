import SwiftUI

// Rain streaks lean with the wind; snow sways. Only wet hours fall in the sky.
enum SkyPrecipitationPainter {
    static func draw(_ sky: SkyInput, time: Double, in context: inout GraphicsContext, size: CGSize) {
        switch sky.kind {
        case .rain, .storm:
            drawRain(sky, time: time, in: &context, size: size)
        case .snow:
            drawSnow(sky, time: time, in: &context, size: size)
        case .dry:
            break
        }
    }

    private static func drawRain(_ sky: SkyInput, time: Double, in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let slant = 0.10 + min(sky.windSpeed, 70) * 0.004
        let base = sky.kind == .storm ? 60.0 : 30.0
        let streaks = Int(min(180, base + sky.precipitation * 10))
        for i in 0..<streaks {
            let seed = Double(i) * 0.91 + 11
            let speed = h * (0.9 + 0.6 * SkyNoise.unit(seed))
            let travel = h + 40
            let fall = (SkyNoise.unit(seed + 1) * travel + time * speed).truncatingRemainder(dividingBy: travel) - 20
            let start = SkyNoise.unit(seed + 2) * w + fall * slant
            let x = ((start.truncatingRemainder(dividingBy: w)) + w).truncatingRemainder(dividingBy: w)
            let length = 10 + SkyNoise.unit(seed + 3) * 10
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: fall))
            streak.addLine(to: CGPoint(x: x - length * slant, y: fall - length))
            context.stroke(
                streak,
                with: .color(Color(red: 0.70, green: 0.82, blue: 0.92).opacity(0.5)),
                lineWidth: 1.1)
        }
    }

    private static func drawSnow(_ sky: SkyInput, time: Double, in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        for i in 0..<70 {
            let seed = Double(i) * 1.7 + 31
            let sway = sin(time * 0.6 + seed) * 10
            let x = SkyNoise.unit(seed) * w + sway
            let travel = h + 20
            let y = (SkyNoise.unit(seed + 1) * travel + time * (14 + SkyNoise.unit(seed + 2) * 16))
                .truncatingRemainder(dividingBy: travel) - 10
            let radius = 1.2 + SkyNoise.unit(seed + 3) * 2.2
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(0.85)))
        }
    }
}
