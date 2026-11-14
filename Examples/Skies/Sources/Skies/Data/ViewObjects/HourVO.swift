// One hour of the forecast. `time` is Open-Meteo's wall time in the city's timezone
// ("yyyy-MM-ddTHH:mm").
struct HourVO: Identifiable, Hashable, Sendable {
    let id: String
    let time: String
    let temperature: Double   // Celsius
    let feelsLike: Double     // Celsius
    let humidity: Double      // percent
    let cloudCover: Double    // percent
    let precipitation: Double // millimetres
    let chance: Double        // percent
    let windSpeed: Double     // km/h
    let pressure: Double      // hPa
    let weatherCode: Int
    let isDay: Bool
    let hour: Double          // local hour of the day, 0..<24
}
