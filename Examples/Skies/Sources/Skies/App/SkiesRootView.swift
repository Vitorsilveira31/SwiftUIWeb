import SwiftUI

// The app's entry point. Both hosts load it: Darwin/Sources/Main.swift on iOS and
// Web/SkiesWebApp.swift in the browser.
public struct SkiesRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ForecastScreen()
                .navigationTitle(Strings.App.title)
        }
    }
}
