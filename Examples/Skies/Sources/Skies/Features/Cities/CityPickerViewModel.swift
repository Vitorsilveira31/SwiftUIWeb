import Foundation
import Observation

// The city sheet's search: the cities whose names contain the query.
@Observable
@MainActor
final class CityPickerViewModel {
    struct State {
        var query = ""
        var results: [CityVO] = []
    }

    enum Action {
        case setQuery(String)
    }

    private(set) var state: State
    private let catalog: [CityVO]

    init(initialState: State = .init(), cities: any CityRepository = CatalogCityRepository()) {
        self.catalog = cities.all
        self.state = initialState
        self.state.results = Self.matches(initialState.query, in: catalog)
    }

    func send(_ action: Action) {
        switch action {
        case .setQuery(let query):
            state.query = query
            state.results = Self.matches(query, in: catalog)
        }
    }

    private static func matches(_ query: String, in cities: [CityVO]) -> [CityVO] {
        cities.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
    }
}
