import Observation

// The notifications on the lock screen. Opening one is the shell's job; this only keeps the stack.
@MainActor
@Observable
final class LockScreenViewModel {
    struct State {
        var notices: [Notice] = []
    }

    enum Action {
        case load
        case clearNotices
    }

    private(set) var state: State
    private let repository: any NoticeRepository

    init(initialState: State = .init(), repository: any NoticeRepository = SampleNoticeRepository()) {
        self.state = initialState
        self.repository = repository
        send(.load)
    }

    func send(_ action: Action) {
        switch action {
        case .load:
            state.notices = repository.notices()
        case .clearNotices:
            state.notices = []
        }
    }
}
