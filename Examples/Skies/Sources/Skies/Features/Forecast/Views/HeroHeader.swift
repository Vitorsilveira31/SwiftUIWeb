import SwiftUI

// The city's name and region, and the button that pauses the sky.
struct HeroHeader: View {
    let city: CityVO
    let paused: Bool
    let onTogglePause: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(city.name)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .accessibilityIdentifier("city-name")
                Text(city.region)
                    .font(.caption)
                    .opacity(0.8)
            }
            Spacer()
            Button(action: onTogglePause) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(paused ? Strings.Forecast.playSky : Strings.Forecast.pauseSky)
            .accessibilityIdentifier("pause-sky")
        }
    }
}
