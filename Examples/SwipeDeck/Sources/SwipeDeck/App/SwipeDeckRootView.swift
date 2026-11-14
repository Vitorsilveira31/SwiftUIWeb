import SwiftUI

// The shared top-level view. Both hosts load it: Darwin/Sources/Main.swift on iOS and Web/SwipeDeckWebApp.swift in
// the browser.
public struct SwipeDeckRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            SwipeDeckView()
                .navigationTitle(Strings.Deck.title)
        }
    }
}
