import Foundation
import Observation

/// The root screen: the selected study, the clock the animated studies read, and the text
/// every study sets. Loaded once from the repository when the screen is created.
@Observable
@MainActor
final class TextStudiesViewModel {
    struct State {
        var study: TextStudy = .balls
        var clock = StudyClock()
        var prose = ProseVO()
        var wallCards: [CardVO] = []
    }

    enum Action {
        case select(TextStudy)
        case togglePlayback
    }

    static let wallCount = 1200

    private(set) var state: State

    init(initialState: State = .init(), repository: any TextStudiesRepository) {
        state = initialState
        state.prose = repository.prose()
        state.wallCards = repository.cards(seed: CardDeck.wallSeed, count: Self.wallCount)
    }

    func send(_ action: Action) {
        switch action {
        case let .select(study):
            state.study = study
        case .togglePlayback:
            state.clock.toggle(at: Date())
        }
    }
}
