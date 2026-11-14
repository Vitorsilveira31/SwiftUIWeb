import SwiftUI

// The big temperature, the condition in words, and the day's high, low and feels-like.
struct HeroReading: View {
    let label: String
    let reading: HourVO
    let day: DayVO?
    let unit: TemperatureUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .opacity(0.8)
                .accessibilityIdentifier("selected-label")
            Text(unit.temperature(reading.temperature))
                .font(.system(size: 92, weight: .light))
                .tracking(-4)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityIdentifier("temperature")
            Text(WeatherCondition.text(code: reading.weatherCode, isDay: reading.isDay))
                .font(.system(.title2, design: .serif))
                .accessibilityIdentifier("condition")
            if let day {
                Text(Strings.Forecast.highLowFeels(
                    high: unit.temperature(day.high),
                    low: unit.temperature(day.low),
                    feelsLike: unit.temperature(reading.feelsLike)))
                    .font(.footnote)
                    .opacity(0.85)
                    .padding(.top, 8)
            }
        }
    }
}
