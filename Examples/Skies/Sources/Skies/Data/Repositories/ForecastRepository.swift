// Where the forecast screen gets a city's forecast.
protocol ForecastRepository: Sendable {
    func forecast(for city: CityVO) async throws -> ForecastVO
}
