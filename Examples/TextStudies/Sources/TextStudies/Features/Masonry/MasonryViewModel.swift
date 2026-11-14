import Observation

/// The masonry study's cards. Shuffle moves to the next seed and lays out a new deck.
@Observable
@MainActor
final class MasonryViewModel {
    struct State {
        var seed = 1
        var cards: [CardVO] = []
    }

    enum Action {
        case shuffle
    }

    static let cardCount = 36

    private(set) var state: State
    private let repository: any TextStudiesRepository

    init(initialState: State = .init(), repository: any TextStudiesRepository) {
        self.repository = repository
        state = initialState
        state.cards = repository.cards(seed: state.seed, count: Self.cardCount)
    }

    func send(_ action: Action) {
        switch action {
        case .shuffle:
            state.seed += 1
            state.cards = repository.cards(seed: state.seed, count: Self.cardCount)
        }
    }
}
