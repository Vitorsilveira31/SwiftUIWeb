import SwiftUI

// The shared top-level view. Both hosts load it: Darwin/Sources/Main.swift on iOS and Web/WrapAroundWebApp.swift in
// the browser.
public struct WrapAroundRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            WrapAroundScreen()
                .navigationTitle(Strings.WrapAround.title)
        }
    }
}
