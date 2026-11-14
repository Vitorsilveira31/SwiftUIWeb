import SwiftUI

// The shared top-level view. Both hosts load it: Darwin/Sources/Main.swift on iOS and Web/PhotoEditorWebApp.swift in
// the browser.
public struct PhotoEditorRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            EditorScreen()
                .navigationTitle(Strings.appTitle)
        }
    }
}
