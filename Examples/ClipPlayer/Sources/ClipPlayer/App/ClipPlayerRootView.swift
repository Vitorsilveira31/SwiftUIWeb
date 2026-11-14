import SwiftUI

// The shared top-level view. Both hosts load it: Darwin/Sources/Main.swift on iOS and Web/ClipPlayerWebApp.swift in
// the browser.
public struct ClipPlayerRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            PlayerView()
                .navigationTitle(Strings.title)
        }
    }
}
