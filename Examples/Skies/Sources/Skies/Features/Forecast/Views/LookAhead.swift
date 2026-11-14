import SwiftUI

// The week: each day's low and high, drawn as a bar across the week's range.
struct LookAhead: View {
    let days: [DayVO]
    let unit: TemperatureUnit

    var body: some View {
        let low = days.map(\.low).min() ?? 0
        let high = days.map(\.high).max() ?? 1
        let spread = max(1, high - low)

        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.Forecast.lookAhead)
                .font(.system(.title2, design: .serif, weight: .semibold))
            Text(Strings.Forecast.dayCount(days.count))
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("forecast-days")
            ForEach(days) { day in
                DayRow(
                    title: day.id == days.first?.id ? Strings.Forecast.today : WallTime.weekday(day.id),
                    day: day,
                    start: (day.low - low) / spread,
                    length: max(0.06, (day.high - day.low) / spread),
                    unit: unit)
            }
        }
        .cardStyle()
    }
}
