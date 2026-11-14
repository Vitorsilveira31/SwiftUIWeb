// A request that failed, or an answer missing a value the screen needs. The screen
// then falls back to the sample rather than showing a partly filled forecast.
enum ForecastError: Error, Sendable {
    case unavailable
    case incomplete
}
