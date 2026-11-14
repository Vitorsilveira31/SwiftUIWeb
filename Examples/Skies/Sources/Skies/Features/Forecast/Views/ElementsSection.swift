import SwiftUI

// Right now, or the selected hour: wind, humidity, feels like, rain, pressure, UV and the sun.
struct ElementsSection: View {
    let reading: HourVO
    let day: DayVO?
    let unit: TemperatureUnit
    let label: String

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.Elements.title)
                .font(.system(.title2, design: .serif, weight: .semibold))
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 14) {
                WindTile(speed: reading.windSpeed, unit: unit)
                ElementTile(
                    title: Strings.Elements.humidity,
                    symbol: "humidity.fill",
                    value: "\(Int(reading.humidity.rounded()))%")
                ElementTile(
                    title: Strings.Elements.feelsLike,
                    symbol: "thermometer.medium",
                    value: unit.temperature(reading.feelsLike))
                    .accessibilityIdentifier("feels-like")
                ElementTile(
                    title: Strings.Elements.rainChance,
                    symbol: "umbrella.fill",
                    value: "\(Int(reading.chance.rounded()))%")
                ElementTile(
                    title: Strings.Elements.pressure,
                    symbol: "gauge.medium",
                    value: "\(Int(reading.pressure.rounded())) \(Strings.Units.hectopascals)")
                ElementTile(
                    title: Strings.Elements.uvIndex,
                    symbol: "sun.max.fill",
                    value: UVIndex.text(day?.uvIndex ?? 0))
                if let day {
                    SunTile(sunrise: day.sunrise, sunset: day.sunset, hour: reading.hour)
                        .gridCellColumns(2)
                }
            }
        }
        .cardStyle()
    }
}
