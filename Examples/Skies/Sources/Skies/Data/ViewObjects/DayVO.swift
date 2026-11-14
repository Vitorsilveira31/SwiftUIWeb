struct DayVO: Identifiable, Hashable, Sendable {
    let id: String            // "yyyy-MM-dd"
    let low: Double           // Celsius
    let high: Double          // Celsius
    let weatherCode: Int
    let chance: Double        // percent
    let sunrise: String
    let sunset: String
    let uvIndex: Double
}
