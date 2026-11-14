import SwiftUI

// Three voices from the system's own faces, so the app bundles no fonts: a heavy
// rounded face for the clock and app marks, a serif for titles, names and actions,
// and the default sans for everything you read.
enum Voice {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    static func text(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
}
