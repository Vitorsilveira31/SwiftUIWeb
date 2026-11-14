import SwiftUI

// The shared top-level view. Both hosts load it: Darwin/Sources/Main.swift on iOS and the
// browser host under Web/.
public struct ShapeGalleryRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            GalleryView()
                .navigationTitle(Strings.title)
        }
    }
}
