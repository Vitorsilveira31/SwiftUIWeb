import Observation

/// Holds what the gallery shows: the page, the step counter and the backdrop switch.
@Observable
@MainActor
final class GalleryViewModel {
    struct State: Sendable {
        var page: GalleryPage = .shapes
        var step = 0
        var backdrop = false
    }

    enum Action {
        case selectPage(GalleryPage)
        case step
        case toggleBackdrop
    }

    static let maxStep = 500

    private(set) var state: State

    init(initialState: State = .init()) {
        self.state = initialState
    }

    func send(_ action: Action) {
        switch action {
        case .selectPage(let page):
            state.page = page
        case .step:
            // Sequence tiles redraw once per step and the resize tile grows with it, so the counter has a ceiling.
            state.step = min(state.step + 1, Self.maxStep)
        case .toggleBackdrop:
            state.backdrop.toggle()
        }
    }
}
