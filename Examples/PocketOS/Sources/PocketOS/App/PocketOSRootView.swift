import SwiftUI

// The shared top-level view. Both hosts load it: Darwin/Sources/Main.swift on iOS and Web/PocketOSWebApp.swift in
// the browser. It owns the phone's view models and the appearance settings every screen reads.
public struct PocketOSRootView: View {
    @AppStorage("pocketos.appearance") private var appearance = "dark"
    @AppStorage("pocketos.textScale") private var textScale = 1.0
    @State private var shell = ShellViewModel()
    @State private var lock = LockScreenViewModel()
    @State private var home = HomeViewModel()
    @State private var messages = MessagesViewModel()
    @State private var reader = ReaderViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            ShellView(shell: shell, lock: lock, home: home, messages: messages, reader: reader)
                .navigationTitle(Strings.Shell.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(Strings.Shell.lock, systemImage: "lock.fill") {
                            shell.send(.lock)
                        }
                        .accessibilityIdentifier("toolbar-lock")
                    }
                }
        }
        .environment(\.readingScale, CGFloat(ReadingScale.clamped(textScale)))
        .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
