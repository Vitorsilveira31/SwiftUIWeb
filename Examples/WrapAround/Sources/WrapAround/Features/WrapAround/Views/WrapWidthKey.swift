import SwiftUI

/// Carries the width the screen is given, so the page can lay itself out to it.
struct WrapWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 390

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
