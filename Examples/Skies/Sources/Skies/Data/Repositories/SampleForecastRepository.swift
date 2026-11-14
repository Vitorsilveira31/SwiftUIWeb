import Foundation

// A fixed forecast, built in code, that the screen shows first and whenever a request
// fails. It is deterministic: the same values on every run.
struct SampleForecastRepository: ForecastRepository {
    static let forecast = make()

    func forecast(for city: CityVO) async throws -> ForecastVO {
        Self.forecast
    }

    private static let dates = [
        "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14",
        "2026-11-15", "2026-11-16", "2026-11-17", "2026-11-18",
    ]

    // Hour indices count from midnight of the first date.
    private static func wallTime(_ index: Int) -> String {
        let pad = { (n: Int) in n < 10 ? "0\(n)" : "\(n)" }
        return "\(dates[index / 24])T\(pad(index % 24)):00"
    }

    private static func make() -> ForecastVO {
        let nowIndex = 14

        func hour(_ index: Int, id: String? = nil) -> HourVO {
            let local = index % 24
            let isDay = local >= 7 && local < 17
            let phase = Double(index - 15) / 24 * 2 * Double.pi
            let temperature = 14 + 5 * cos(phase)
            let cloud = min(max(40 + 35 * sin(Double(index) * 0.7), 0), 100)
            let rain = max(0, sin(Double(index) * 0.45) - 0.7) * 4
            let code: Int
            if rain > 0.2 { code = 61 } else if cloud > 60 { code = 3 } else if cloud > 30 { code = 2 } else { code = isDay ? 0 : 1 }
            let time = wallTime(index)
            return HourVO(
                id: id ?? time,
                time: time,
                temperature: temperature,
                feelsLike: temperature - 1.5,
                humidity: 62 + 18 * sin(Double(index) * 0.5),
                cloudCover: cloud,
                precipitation: rain,
                chance: min(100, rain * 25),
                windSpeed: 12 + 9 * abs(sin(Double(index) * 0.5)),
                pressure: 1016 + 4 * sin(Double(index) * 0.3),
                weatherCode: code,
                isDay: isDay,
                hour: Double(local))
        }

        let current = hour(nowIndex, id: "now")
        let hours = (nowIndex + 1...nowIndex + 24).map { hour($0) }

        let lows = [9.0, 8, 10, 12, 11, 9, 8]
        let highs = [17.0, 16, 19, 18, 15, 14, 16]
        let codes = [2, 61, 3, 1, 0, 3, 2]
        let chances = [20.0, 80, 30, 10, 0, 40, 15]
        let uv = [3.1, 1.9, 2.4, 4.0, 4.6, 2.2, 1.5]
        let days = (0..<7).map { i in
            DayVO(
                id: dates[i],
                low: lows[i],
                high: highs[i],
                weatherCode: codes[i],
                chance: chances[i],
                sunrise: "\(dates[i])T07:\(10 + i):00",
                sunset: "\(dates[i])T16:\(50 + i):00",
                uvIndex: uv[i])
        }

        return ForecastVO(
            current: current,
            hours: hours,
            days: days,
            updated: "2026-11-11 · 14:00",
            source: .sample)
    }
}
