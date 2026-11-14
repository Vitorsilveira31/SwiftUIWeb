import SwiftUI

// One day of the week: its name, symbol, chance of rain and the range bar.
struct DayRow: View {
    let title: String
    let day: DayVO
    let start: Double
    let length: Double
    let unit: TemperatureUnit

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(width: 52, alignment: .leading)
            Image(systemName: WeatherCondition.symbol(code: day.weatherCode, isDay: true))
                .foregroundStyle(.orange)
                .frame(width: 26)
                .accessibilityLabel(WeatherCondition.text(code: day.weatherCode, isDay: true))
            Text("\(Int(day.chance.rounded()))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(unit.temperature(day.low))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            RangeBar(start: start, length: length)
                .frame(height: 6)
            Text(unit.temperature(day.high))
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}
