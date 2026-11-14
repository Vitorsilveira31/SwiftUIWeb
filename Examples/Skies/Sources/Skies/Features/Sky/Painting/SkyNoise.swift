import Foundation

enum SkyNoise {
    // A cheap, deterministic hash in 0..<1, so the sky is the same on every run.
    static func unit(_ x: Double) -> Double {
        let s = sin(x * 12.9898 + 78.233) * 43758.5453
        return s - floor(s)
    }
}
