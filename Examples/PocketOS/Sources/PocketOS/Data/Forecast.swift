struct Forecast: Hashable, Sendable {
    struct Hour: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        let temperature: Int
        let symbol: String
    }

    let place: String
    let temperature: Int
    let condition: String
    let high: Int
    let low: Int
    let hours: [Hour]
}
