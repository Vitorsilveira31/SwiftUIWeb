import SwiftUI

// The shared top-level view. Both hosts load it: Darwin/Sources/Main.swift on iOS and Web/MarkdownReaderWebApp.swift in
// the browser.
public struct MarkdownReaderRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ReaderScreen()
                .navigationTitle(Strings.App.title)
        }
    }
}
