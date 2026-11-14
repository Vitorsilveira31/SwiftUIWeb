import SwiftUI

// The phone's phases: the lock screen, then the home screen, with an app zooming open over it.
struct ShellView: View {
    let shell: ShellViewModel
    let lock: LockScreenViewModel
    let home: HomeViewModel
    let messages: MessagesViewModel
    let reader: ReaderViewModel

    @Namespace private var zoom

    var body: some View {
        ZStack {
            if shell.state.stage == .lock {
                LockScreenView(lock: lock, shell: shell)
                    .transition(.opacity)
            } else {
                HomeScreenView(home: home, shell: shell, unreadCount: messages.state.unread.count, zoom: zoom)
                    .transition(.opacity)
                if let app = shell.state.presentedApp {
                    AppScreen(app: app, shell: shell, messages: messages, reader: reader, zoom: zoom)
                        .transition(.identity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The zoom: the matched tile and the app's ground animate together.
        .animation(.smooth(duration: 0.5), value: shell.state.presentedApp)
        .animation(.smooth, value: shell.state.stage)
        .overlay(alignment: .bottom) {
            Toast(text: shell.state.toast)
        }
        .animation(.smooth, value: shell.state.toastSerial)
        .task(id: shell.state.toastSerial) {
            guard shell.state.toast != nil else { return }
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled {
                shell.send(.clearToast)
            }
        }
    }
}
