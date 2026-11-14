import SwiftUI

// An open app. Its ground is the zoom's matched partner: it grows out of the tile that
// opened it. The Home bar along the bottom returns to the home screen.
struct AppScreen: View {
    let app: PhoneApp
    let shell: ShellViewModel
    let messages: MessagesViewModel
    let reader: ReaderViewModel
    let zoom: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            StatusBar()
            switch app {
            case .messages:
                MessagesView(messages: messages, shell: shell)
            case .reader:
                ReaderView(reader: reader, messages: messages, shell: shell)
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.background)
                .matchedGeometryEffect(id: app.rawValue, in: zoom)
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HomeBar {
                shell.send(.goHome)
            }
        }
    }
}
