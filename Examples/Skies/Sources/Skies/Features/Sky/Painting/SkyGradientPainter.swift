import SwiftUI

// The sky's base: a vertical gradient from day or night, pulled toward dusk and storm colours.
enum SkyGradientPainter {
    static func draw(_ sky: SkyInput, in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let day = sky.day
        let twilight = sky.twilight
        let stormy = sky.stormy

        var upper = SkyPalette.mix(SkyPalette.nightTop, SkyPalette.dayTop, day)
        upper = SkyPalette.mix(upper, (0.11, 0.12, 0.25), twilight * 0.65)
        var lower = SkyPalette.mix(SkyPalette.nightLow, SkyPalette.dayLow, day)
        lower = SkyPalette.mix(lower, SkyPalette.dusk, twilight * 0.88)
        upper = SkyPalette.mix(upper, SkyPalette.storm, stormy * 0.65)
        lower = SkyPalette.mix(lower, SkyPalette.storm, stormy * 0.65)

        context.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h)),
            with: .linearGradient(
                Gradient(colors: [SkyPalette.color(upper), SkyPalette.color(lower)]),
                startPoint: CGPoint(x: w / 2, y: 0),
                endPoint: CGPoint(x: w / 2, y: h)))
    }
}
