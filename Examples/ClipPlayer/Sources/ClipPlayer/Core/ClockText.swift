/// Seconds as m:ss, with an optional sign ("-" for time left).
enum ClockText {
    static func text(_ seconds: Double, sign: String = "") -> String {
        guard seconds.isFinite else { return "\(sign)0:00" }
        // Clamp before converting: Int is 32 bits in the browser build, and a longer media time would trap.
        let total = Int(min(max(seconds.rounded(.down), 0), 1_000_000_000))
        let minutes = total / 60
        let rest = total % 60
        let padding = rest < 10 ? "0" : ""
        return "\(sign)\(minutes):\(padding)\(rest)"
    }
}
