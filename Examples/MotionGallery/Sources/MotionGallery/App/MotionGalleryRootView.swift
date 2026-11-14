import SwiftUI

// The shared top-level view. Both hosts load it: Darwin/Sources/Main.swift on iOS and Web/MotionGalleryWebApp.swift in
// the browser.
public struct MotionGalleryRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            GalleryView()
                .navigationTitle(Strings.App.title)
        }
    }
}
