import SwiftUI

/// A lit sphere inside a tilted ring, drawn as characters. The light circles with the clock.
struct AsciiStudyView: View {
    let clock: StudyClock
    @State private var face: AsciiFace = .monospaced
    @State private var proportional = WidthCache(font: TextFonts.glyph)
    @State private var monospaced = WidthCache(font: TextFonts.mono)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: Strings.Ascii.eyebrow)
            Picker(Strings.Ascii.facePicker, selection: $face) {
                ForEach(AsciiFace.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ascii-face")
            Text(face.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !clock.isRunning)) { timeline in
                Canvas { context, _ in
                    AsciiScene.draw(
                        into: &context,
                        face: face,
                        seconds: clock.elapsed(at: timeline.date),
                        proportional: proportional,
                        monospaced: monospaced)
                }
                .frame(width: AsciiScene.width,
                       height: CGFloat(AsciiScene.rows) * AsciiScene.rowHeight)
                .accessibilityIdentifier("ascii-art")
            }
        }
        .padding()
    }
}
