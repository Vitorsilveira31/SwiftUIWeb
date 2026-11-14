import SwiftUI

// The next 24 hours as a horizontal strip. Choosing a card moves the hero to it.
struct HourStrip: View {
    let hours: [HourVO]
    let selection: String
    let unit: TemperatureUnit
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Forecast.theDayUnfolding)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text(Strings.Forecast.chooseHour)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Strings.Forecast.next24Hours)
                    .font(.caption2.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    HourCard(
                        title: Strings.Forecast.now,
                        symbol: "dot.radiowaves.left.and.right",
                        primary: Strings.Forecast.live,
                        secondary: Strings.Forecast.today,
                        selected: selection == "now"
                    ) {
                        onSelect("now")
                    }
                    .accessibilityIdentifier("hour-now")

                    ForEach(hours) { hour in
                        HourCard(
                            title: WallTime.hourLabel(hour.time),
                            symbol: WeatherCondition.symbol(code: hour.weatherCode, isDay: hour.isDay),
                            primary: unit.temperature(hour.temperature),
                            secondary: "\(Int(hour.chance.rounded()))%",
                            selected: selection == hour.id
                        ) {
                            onSelect(hour.id)
                        }
                        .accessibilityIdentifier("hour-\(hour.id)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
