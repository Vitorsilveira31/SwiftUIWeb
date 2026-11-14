import Observation

/// The market list's state. A tick replaces the coins in one step, so only the
/// charts whose data changed are redrawn; `frozen` is read by every row.
@Observable
@MainActor
final class MarketsViewModel {
    struct State {
        var coins: [CoinVO] = []
        var version = 0
        var frozen = false
    }

    enum Action {
        case tick
        case toggleFreeze
    }

    private(set) var state: State
    private let repository: any CoinRepository

    init(initialState: State = .init(), repository: any CoinRepository = SampleCoinRepository()) {
        self.repository = repository
        var state = initialState
        if state.coins.isEmpty {
            state.coins = repository.coins(version: state.version)
        }
        self.state = state
    }

    func send(_ action: Action) {
        switch action {
        case .tick:
            state.version += 1
            state.coins = repository.coins(version: state.version)
        case .toggleFreeze:
            state.frozen.toggle()
        }
    }
}
