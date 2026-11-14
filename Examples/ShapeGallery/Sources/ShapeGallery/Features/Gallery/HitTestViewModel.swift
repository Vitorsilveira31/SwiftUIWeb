import Observation

// The part of a picture that was tapped last. Its raw value is shown beside the grid.
enum HitPick: String, Sendable {
    case none, back, disc, bars, line
}

@Observable @MainActor final class HitTestViewModel {
    struct State {
        var picked: HitPick = .none
    }

    enum Action {
        case picked(HitPick)
    }

    private(set) var state: State

    init(initialState: State = .init()) {
        self.state = initialState
    }

    func send(_ action: Action) {
        switch action {
        case .picked(let pick):
            state.picked = pick
        }
    }
}
