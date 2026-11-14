import Foundation
import SwiftUI
#if !WEB
    import Observation
    import SkipFuse
#endif

@Observable @MainActor final class CounterViewModel {
    struct State: Equatable {
        var count = 0
        var step = 1
    }

    enum Action {
        case increment, decrement, reset
        case setStep(Int)
    }

    private(set) var state = State()

    func send(_ action: Action) {
        switch action {
        case .increment: state.count += state.step
        case .decrement: state.count -= state.step
        case .reset: state.count = 0
        case let .setStep(step): state.step = step
        }
    }
}
