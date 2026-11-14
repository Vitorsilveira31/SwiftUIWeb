/// The pulse's keyframes: radius 3 to 9 and opacity 0.5 to 0, 1.2 s per cycle,
/// ease-out, and the first cycle waits 0.6 s (the draw-in) before it shows.
enum PulseKeyframes {
    static let cycle = 1.2
    static let delay = 0.6
    /// Frozen at 300 ms into the cycle: the reference's paused `-300ms` delay.
    static let frozenProgress = 0.25

    static func ring(elapsed: Double?) -> (radius: Double, opacity: Double) {
        let progress: Double
        if let elapsed {
            guard elapsed >= delay else { return (3, 0) }
            progress = (elapsed - delay).truncatingRemainder(dividingBy: cycle) / cycle
        } else {
            progress = frozenProgress
        }
        let eased = 1 - (1 - progress) * (1 - progress)
        return (3 + 6 * eased, 0.5 * (1 - eased))
    }
}
