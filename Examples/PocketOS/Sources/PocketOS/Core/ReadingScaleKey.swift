import SwiftUI

// The reading-size multiplier from Settings. The root reads the setting once and
// passes it down, so no screen has to read it itself.
struct ReadingScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

/// The range the Settings slider allows. The stored value is clamped to it wherever it is read,
/// because local storage can hold anything.
enum ReadingScale {
    static let range: ClosedRange<Double> = 0.85...1.3

    static func clamped(_ stored: Double) -> Double {
        stored.isFinite ? min(max(stored, range.lowerBound), range.upperBound) : 1
    }
}

extension EnvironmentValues {
    var readingScale: CGFloat {
        get { self[ReadingScaleKey.self] }
        set { self[ReadingScaleKey.self] = newValue }
    }
}
