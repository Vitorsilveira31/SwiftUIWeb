import Observation

// Owns the city, the units and the forecast. The sample is on screen from the first
// frame; a successful request replaces it, and a failed one puts it back with a notice.
@Observable
@MainActor
final class ForecastViewModel {
    enum LoadState: Hashable, Sendable {
        case loading
        case loaded
        case failed(String)

        var failureMessage: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    struct State {
        var city: CityVO = CatalogCityRepository.defaultCity
        var units: TemperatureUnit = .fahrenheit
        var loadState: LoadState = .loading
        var forecast: ForecastVO = SampleForecastRepository.forecast
        var selection = "now"
    }

    enum Action {
        case appear
        case refresh
        case selectCity(CityVO)
        case useCurrentLocation
        case setUnits(TemperatureUnit)
        case selectHour(String)
    }

    private(set) var state: State
    private let forecasts: any ForecastRepository
    private let cities: any CityRepository
    // Each request takes a serial number, so an answer for a city the person has since left is ignored.
    private var serial = 0

    init(
        initialState: State = .init(),
        forecasts: any ForecastRepository = OpenMeteoForecastRepository(),
        cities: any CityRepository = CatalogCityRepository()
    ) {
        self.state = initialState
        self.forecasts = forecasts
        self.cities = cities
    }

    // Returns the request the action started, if any, so a pull to refresh can wait for it.
    @discardableResult
    func send(_ action: Action) -> Task<Void, Never>? {
        switch action {
        case .appear, .refresh:
            return load()
        case .selectCity(let city):
            return choose(city)
        case .useCurrentLocation:
            return choose(cities.currentLocation)
        case .setUnits(let units):
            state.units = units
        case .selectHour(let id):
            state.selection = id
        }
        return nil
    }

    private func choose(_ city: CityVO) -> Task<Void, Never>? {
        guard city.id != state.city.id else { return nil }
        state.city = city
        state.selection = "now"
        state.forecast = SampleForecastRepository.forecast
        return load()
    }

    private func load() -> Task<Void, Never> {
        serial += 1
        let current = serial
        let target = state.city
        state.loadState = .loading
        return Task { await self.fetch(target, serial: current) }
    }

    private func fetch(_ city: CityVO, serial current: Int) async {
        do {
            let fresh = try await forecasts.forecast(for: city)
            guard current == serial else { return }
            state.forecast = fresh
            state.loadState = .loaded
        } catch {
            guard current == serial else { return }
            state.forecast = SampleForecastRepository.forecast
            state.loadState = .failed(Strings.Forecast.failure)
        }
    }
}
