import Foundation

/// The clock the animated studies read. It only advances while running, so Pause freezes
/// the balls and the ASCII light rather than letting them jump on resume.
struct StudyClock: Equatable, Sendable {
    private var accumulated: TimeInterval = 0
    private var resumedAt: Date? = Date()

    var isRunning: Bool { resumedAt != nil }

    mutating func toggle(at date: Date) {
        if let resumedAt {
            accumulated += date.timeIntervalSince(resumedAt)
            self.resumedAt = nil
        } else {
            resumedAt = date
        }
    }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (resumedAt.map { date.timeIntervalSince($0) } ?? 0)
    }
}
