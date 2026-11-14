import Observation

// The home screen's content: the tiles, the dock, today's event, the forecast and the lead article.
@MainActor
@Observable
final class HomeViewModel {
    struct State {
        var tiles: [Tile] = []
        var dock: [Tile] = []
        var event: CalendarEvent?
        var forecast: Forecast?
        var lead: Article?
    }

    enum Action {
        case load
    }

    private(set) var state: State
    private let home: any HomeRepository
    private let articles: any ArticleRepository

    init(
        initialState: State = .init(),
        home: any HomeRepository = SampleHomeRepository(),
        articles: any ArticleRepository = SampleArticleRepository()
    ) {
        self.state = initialState
        self.home = home
        self.articles = articles
        send(.load)
    }

    func send(_ action: Action) {
        switch action {
        case .load:
            state.tiles = home.tiles()
            state.dock = home.dock()
            state.event = home.event()
            state.forecast = home.forecast()
            state.lead = articles.articles().first
        }
    }
}
