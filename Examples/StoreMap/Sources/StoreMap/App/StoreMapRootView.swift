import SwiftUI

// The shared top-level view. Both hosts load it: Darwin/Sources/Main.swift on iOS and Web/StoreMapWebApp.swift in
// the browser.
public struct StoreMapRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            StoreMapScreen()
                .navigationTitle(Strings.Stores.title)
        }
    }
}
