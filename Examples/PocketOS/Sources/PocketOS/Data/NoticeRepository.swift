// The notifications waiting on the lock screen.
protocol NoticeRepository: Sendable {
    func notices() -> [Notice]
}
