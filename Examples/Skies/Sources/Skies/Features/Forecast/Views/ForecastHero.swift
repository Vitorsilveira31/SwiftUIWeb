import SwiftUI

// The city's current conditions, or the chosen hour's, over the animated sky. The sky
// is a fixed dark scene, so its type is white in both schemes.
struct ForecastHero: View {
    let city: CityVO
    let reading: HourVO
    let day: DayVO?
    let isNow: Bool
    let loading: Bool
    let unit: TemperatureUnit
    let paused: Bool
    let onTogglePause: () -> Void
    let onBackToNow: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            SkyCanvas(sky: SkyInput(reading), paused: paused)

            VStack(alignment: .leading, spacing: 0) {
                HeroHeader(city: city, paused: paused, onTogglePause: onTogglePause)
                Spacer(minLength: 24)
                HeroReading(label: label, reading: reading, day: day, unit: unit)
                Spacer(minLength: 16)
                HeroFooter(summary: HourSummary.text(for: reading), isNow: isNow, onBackToNow: onBackToNow)
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .frame(maxWidth: .infinity, minHeight: 440, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var label: String {
        if loading { return Strings.Forecast.updatingForecast }
        if isNow { return Strings.Forecast.rightNow }
        let weekday = WallTime.weekday(String(reading.time.prefix(10)))
        return Strings.Forecast.dayHourForecast(weekday, WallTime.clock(reading.time))
    }
}
