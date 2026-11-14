import SwiftUI

// The appearance and the reading size. The root reads both to apply them to every screen.
struct DisplaySection: View {
    @AppStorage("pocketos.appearance") private var appearance = "dark"
    @AppStorage("pocketos.textScale") private var textScale = 1.0

    var body: some View {
        Section(Strings.Settings.display) {
            Picker(Strings.Settings.appearance, selection: $appearance) {
                Text(Strings.Settings.dark).tag("dark")
                Text(Strings.Settings.light).tag("light")
                Text(Strings.Settings.automatic).tag("system")
            }
            .accessibilityIdentifier("appearance")
            Slider(value: $textScale, in: 0.85...1.3, step: 0.01) {
                Text(Strings.Settings.textSize)
            } minimumValueLabel: {
                Text(Strings.Settings.smallA).font(.caption)
            } maximumValueLabel: {
                Text(Strings.Settings.smallA).font(.title2)
            }
            .accessibilityIdentifier("text-size")
            Text("The quick brown fox jumps over the lazy dog.")
                .font(Voice.text(17 * CGFloat(ReadingScale.clamped(textScale))))
        }
    }
}
