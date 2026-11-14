/// Every user-visible text of the app.
enum Strings {
    enum App {
        static let title = "Motion Gallery"
    }

    enum Gallery {
        static let pagePicker = "Page"
        static let fixtures = "Fixtures"
        static let shimmer = "Shimmer"
        static let restart = "Restart"
        static let imagesHeader = "Images"
        static let keyframesHeader = "Keyframes"
    }

    enum Images {
        static let fourFrames = "Four frames, uneven delays"
        static let threeFrames = "Three frames, played once"
        static let zeroDelays = "Zero delays"
        static let largeGif = "A large GIF shown small"
        static let webpTwice = "A WebP played twice"
        static let webpAlpha = "A WebP with alpha"
        static let rounded = "Rounded"
    }

    enum Keyframes {
        static let sweep = "sweep, 1s linear, infinite"
        static let pulse = "pulse, 800ms ease-in-out, alternate"
        static let spin = "spin, 1200ms linear, infinite"
        static let glow = "glow, 1s ease, alternate"
        static let steps = "walk, 1s steps(4), infinite"
        static let tour = "tour, 1500ms, three keyframes"
        static let origin = "spin from a top-left origin, 2s"
        static let held = "spin, delayed -250ms and paused"
    }
}
