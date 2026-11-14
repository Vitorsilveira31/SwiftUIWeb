import SwiftUI

// The sky is a Canvas redrawn by a TimelineView. Paused, the timeline stops and the
// last frame stays; reduce motion starts paused, so the sky is still but drawn.
struct SkyCanvas: View {
    let sky: SkyInput
    let paused: Bool

    var body: some View {
        TimelineView(.animation(paused: paused)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                SkyGradientPainter.draw(sky, in: &context, size: size)
                SkyStarsPainter.draw(sky, time: time, in: &context, size: size)
                SkySunPainter.draw(sky, in: &context, size: size)
                SkyCloudsPainter.draw(sky, time: time, in: &context, size: size)
                SkyRidgesPainter.draw(sky, in: &context, size: size)
                SkyPrecipitationPainter.draw(sky, time: time, in: &context, size: size)
            }
        }
    }
}
