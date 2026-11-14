import Observation

// The articles in the library. The lead article is the first one.
@MainActor
@Observable
final class ReaderViewModel {
    struct State {
        var articles: [Article] = []
    }

    enum Action {
        case load
    }

    private(set) var state: State
    private let repository: any ArticleRepository

    init(initialState: State = .init(), repository: any ArticleRepository = SampleArticleRepository()) {
        self.state = initialState
        self.repository = repository
        send(.load)
    }

    func send(_ action: Action) {
        switch action {
        case .load:
            state.articles = repository.articles()
        }
    }
}
