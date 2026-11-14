import SwiftUI

// The shared top-level view. Both hosts load it: Darwin/Sources/Main.swift on iOS and Web/CarouselWebApp.swift in
// the browser.
public struct CarouselRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            CardsView()
        }
    }
}
