import Observation

/// The two pages of the gallery.
enum GalleryPage: Hashable, Sendable {
    case fixtures
    case shimmer
}

@Observable
@MainActor
final class GalleryViewModel {
    struct State: Equatable, Sendable {
        var page = GalleryPage.fixtures
        /// Restart bumps this; the page content is keyed by it, so every tile is rebuilt and replays.
        var generation = 0
    }

    enum Action {
        case selectPage(GalleryPage)
        case restart
    }

    private(set) var state: State

    init(initialState: State = .init()) {
        self.state = initialState
    }

    func send(_ action: Action) {
        switch action {
        case .selectPage(let page):
            state.page = page
        case .restart:
            state.generation += 1
        }
    }
}
