import Observation

// The phone's phases (lock, then home), the app open over home, and the place inside
// that app. The toast lives here because any screen can raise one.
@MainActor
@Observable
final class ShellViewModel {
    enum Stage: Sendable { case lock, home }

    struct State {
        var stage = Stage.lock
        var presentedApp: PhoneApp?
        var openedThread: String?
        var openedArticle: String?
        var toast: String?
        var toastSerial = 0
    }

    enum Action {
        case unlock
        case lock
        case goHome
        case open(PhoneApp)
        case openThread(String)
        case closeThread
        case openArticle(String)
        case closeArticle
        case activate(Destination?, name: String)
        case openNotice(Notice)
        case clearToast
    }

    private(set) var state: State

    init(initialState: State = .init()) {
        self.state = initialState
    }

    func send(_ action: Action) {
        switch action {
        case .unlock:
            state.stage = .home
        case .lock:
            state.stage = .lock
            closeApp()
        case .goHome:
            closeApp()
        case .open(let app):
            state.presentedApp = app
            state.openedThread = nil
            state.openedArticle = nil
        case .openThread(let id):
            state.presentedApp = .messages
            state.openedThread = id
            state.openedArticle = nil
        case .closeThread:
            state.openedThread = nil
        case .openArticle(let id):
            state.presentedApp = .reader
            state.openedArticle = id
            state.openedThread = nil
        case .closeArticle:
            state.openedArticle = nil
        case .activate(let destination, let name):
            activate(destination, name: name)
        case .openNotice(let notice):
            // A notice unlocks the phone and opens what it is about.
            state.stage = .home
            activate(notice.destination, name: notice.title)
        case .clearToast:
            state.toast = nil
        }
    }

    private func closeApp() {
        state.presentedApp = nil
        state.openedThread = nil
        state.openedArticle = nil
    }

    private func activate(_ destination: Destination?, name: String) {
        switch destination {
        case .app(let app)?: send(.open(app))
        case .thread(let id)?: send(.openThread(id))
        case .article(let id)?: send(.openArticle(id))
        case nil: showToast(Strings.Shell.unavailable(name))
        }
    }

    private func showToast(_ text: String) {
        state.toast = text
        state.toastSerial += 1
    }
}
