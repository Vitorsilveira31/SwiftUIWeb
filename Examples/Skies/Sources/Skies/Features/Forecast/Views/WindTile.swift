import SwiftUI

// The wind's speed, beside a compass rose that fills with it.
struct WindTile: View {
    let speed: Double
    let unit: TemperatureUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Strings.Elements.wind, systemImage: "wind")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .center) {
                Text(unit.wind(speed))
                    .font(.system(.title2, design: .serif))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityIdentifier("wind")
                Spacer(minLength: 4)
                Compass(speed: speed)
                    .frame(width: 70, height: 70)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.10)))
    }
}
