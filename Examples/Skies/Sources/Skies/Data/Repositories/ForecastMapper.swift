// Turns the wire shape into the screen's values, rejecting anything incomplete
// rather than showing a partly filled forecast.
enum ForecastMapper {
    /// Hours read from the response. The screen needs 24 upcoming hours; the cap bounds the work on a bad response.
    private static let maxHours = 400

    // Physically plausible ranges. A value outside its range is clamped, so the Int conversions below stay in range.
    private static let temperatureRange: ClosedRange<Double> = -100...100
    private static let percentRange: ClosedRange<Double> = 0...100
    private static let windRange: ClosedRange<Double> = 0...500
    private static let pressureRange: ClosedRange<Double> = 0...2000
    private static let precipitationRange: ClosedRange<Double> = 0...1000
    private static let uvRange: ClosedRange<Double> = 0...20
    private static let weatherCodeRange: ClosedRange<Double> = 0...99
    private static let flagRange: ClosedRange<Double> = 0...1

    static func make(_ wire: ForecastResponse) throws -> ForecastVO {
        let now = wire.current.time
        guard now.count == 16 else { throw ForecastError.incomplete }
        let h = wire.hourly

        let hours = try (0..<min(h.time.count, maxHours)).map { i -> HourVO in
            let time = h.time[i]
            guard time.count == 16 else { throw ForecastError.incomplete }
            return try HourVO(
                id: time,
                time: time,
                temperature: value(h.temperature2M, i, temperatureRange),
                feelsLike: value(h.apparentTemperature, i, temperatureRange),
                humidity: value(h.relativeHumidity2M, i, percentRange),
                cloudCover: value(h.cloudCover, i, percentRange),
                precipitation: value(h.precipitation, i, precipitationRange),
                chance: value(h.precipitationProbability, i, percentRange),
                windSpeed: value(h.windSpeed10M, i, windRange),
                pressure: value(h.pressureMsl, i, pressureRange),
                weatherCode: Int(value(h.weatherCode, i, weatherCodeRange)),
                isDay: value(h.isDay, i, flagRange) == 1,
                hour: WallTime.hour(of: time))
        }

        // The current hour's rain chance comes from the hourly list, as in the reference.
        guard let thisHour = hours.first(where: { $0.time.prefix(13) == now.prefix(13) }) else {
            throw ForecastError.incomplete
        }
        let c = wire.current
        let current = try HourVO(
            id: "now",
            time: now,
            temperature: plausible(c.temperature2M, temperatureRange),
            feelsLike: plausible(c.apparentTemperature, temperatureRange),
            humidity: plausible(c.relativeHumidity2M, percentRange),
            cloudCover: plausible(c.cloudCover, percentRange),
            precipitation: plausible(c.precipitation, precipitationRange),
            chance: thisHour.chance,
            windSpeed: plausible(c.windSpeed10M, windRange),
            pressure: plausible(c.pressureMsl, pressureRange),
            weatherCode: Int(plausible(c.weatherCode, weatherCodeRange)),
            isDay: plausible(c.isDay, flagRange) == 1,
            hour: WallTime.hour(of: now))

        let upcoming = Array(hours.filter { $0.time > now }.prefix(24))
        guard upcoming.count == 24 else { throw ForecastError.incomplete }

        let d = wire.daily
        guard d.time.count >= 7 else { throw ForecastError.incomplete }
        let days = try (0..<7).map { i -> DayVO in
            try DayVO(
                id: d.time[i],
                low: value(d.temperature2MMin, i, temperatureRange),
                high: value(d.temperature2MMax, i, temperatureRange),
                weatherCode: Int(value(d.weatherCode, i, weatherCodeRange)),
                chance: value(d.precipitationProbabilityMax, i, percentRange),
                sunrise: text(d.sunrise, i),
                sunset: text(d.sunset, i),
                uvIndex: value(d.uvIndexMax, i, uvRange))
        }

        return ForecastVO(
            current: current,
            hours: upcoming,
            days: days,
            updated: "\(now.prefix(10)) · \(now.suffix(5))",
            source: .live)
    }

    private static func value(_ array: [Double], _ i: Int, _ range: ClosedRange<Double>) throws -> Double {
        guard i < array.count else { throw ForecastError.incomplete }
        return try plausible(array[i], range)
    }

    /// Rejects NaN and infinite values, and clamps the rest into `range`.
    private static func plausible(_ number: Double, _ range: ClosedRange<Double>) throws -> Double {
        guard number.isFinite else { throw ForecastError.incomplete }
        return min(max(number, range.lowerBound), range.upperBound)
    }

    private static func text(_ array: [String], _ i: Int) throws -> String {
        guard i < array.count else { throw ForecastError.incomplete }
        return array[i]
    }
}
