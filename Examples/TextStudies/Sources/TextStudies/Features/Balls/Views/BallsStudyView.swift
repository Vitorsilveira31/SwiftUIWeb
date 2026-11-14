import SwiftUI

/// Three spheres bounce across a paragraph. Positions are a pure function of the clock, and
/// the text is re-broken from the same widths on every frame.
struct BallsStudyView: View {
    let clock: StudyClock
    let words: [String]
    @State private var widths = WidthCache(font: TextFonts.body)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: Strings.Balls.eyebrow)
            Text(Strings.Balls.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            TimelineView(.animation(paused: !clock.isRunning)) { timeline in
                Canvas { context, size in
                    BallScene.draw(
                        into: &context,
                        size: size,
                        elapsed: CGFloat(clock.elapsed(at: timeline.date) * 1000),
                        widths: widths,
                        words: words)
                }
            }
            .frame(height: 460)
            .accessibilityIdentifier("balls-page")
        }
        .padding()
    }
}
