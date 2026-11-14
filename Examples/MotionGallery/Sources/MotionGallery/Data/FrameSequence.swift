import SwiftUI

/// The frames of one image: each frame is a coloured square whose white quarter
/// moves clockwise one quarter per frame. The reference's images are GIF/WebP files,
/// which SwiftUI cannot animate, so the tiles draw the same idea from a timeline.
struct FrameSequence: Sendable {
    let colour: Color
    /// Seconds each frame stays on screen. Browsers clamp GIF delays of 10 ms or less
    /// to 100 ms, so the zero-delay sequence uses 0.1 for every frame.
    let delays: [Double]
    /// How many times the sequence runs; nil loops forever. A finished sequence holds its last frame.
    let plays: Int?
    var alpha: Double = 1
    var inset: CGFloat = 0

    // The per-frame delays of the reference files were not read (see NOTES.md),
    // so these timings and colours are the demo's own.
    static let spin = FrameSequence(
        colour: Color(red: 13 / 255, green: 148 / 255, blue: 136 / 255),
        delays: [0.2, 0.1, 0.3, 0.1],
        plays: nil
    )
    static let once = FrameSequence(
        colour: Color(red: 234 / 255, green: 88 / 255, blue: 12 / 255),
        delays: [0.2, 0.2, 0.2],
        plays: 1
    )
    static let zero = FrameSequence(
        colour: Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255),
        delays: [0.1, 0.1, 0.1, 0.1],
        plays: nil
    )
    static let large = FrameSequence(
        colour: Color(red: 225 / 255, green: 29 / 255, blue: 72 / 255),
        delays: [0.1, 0.1, 0.1, 0.1],
        plays: nil
    )
    static let twice = FrameSequence(
        colour: Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255),
        delays: [0.15, 0.15, 0.15, 0.15],
        plays: 2
    )
    static let alpha = FrameSequence(
        colour: Color(red: 2 / 255, green: 132 / 255, blue: 199 / 255),
        delays: [0.2, 0.2],
        plays: nil,
        alpha: 0.6,
        inset: 8
    )

    /// The frame showing at `elapsed` seconds after the sequence started.
    func frameIndex(elapsed: Double) -> Int {
        let loop = delays.reduce(0, +)
        if let plays, elapsed >= Double(plays) * loop {
            return delays.count - 1
        }
        var t = elapsed.truncatingRemainder(dividingBy: loop)
        for (index, delay) in delays.enumerated() {
            if t < delay { return index }
            t -= delay
        }
        return delays.count - 1
    }
}
