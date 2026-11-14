import Foundation

// What the sky draws, read from the selected hour: the same inputs as the reference's
// shader (cloud cover, precipitation, wind, daylight, local hour).
struct SkyInput: Equatable, Sendable {
    let cloudCover: Double      // 0...100
    let precipitation: Double   // millimetres, 0...20
    let kind: PrecipitationKind
    let isDay: Bool
    let hour: Double            // local hour, 0...24
    let windSpeed: Double       // km/h

    init(_ reading: HourVO) {
        cloudCover = min(max(reading.cloudCover, 0), 100)
        precipitation = min(max(reading.precipitation, 0), 20)
        kind = WeatherCondition.precipitation(code: reading.weatherCode, amount: reading.precipitation)
        isDay = reading.isDay
        hour = reading.hour
        windSpeed = min(max(reading.windSpeed, 0), 150)
    }

    var day: Double { isDay ? 1 : 0 }

    // Glows around dawn (06:30) and dusk (18:30), strongest at their centres.
    var twilight: Double {
        max(exp(-pow((hour - 6.5) / 1.8, 2)), exp(-pow((hour - 18.5) / 2.0, 2)))
    }

    var stormy: Double { min(max(precipitation * 0.22, 0), 0.8) }
}
