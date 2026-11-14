// Threads, their conversations and which of them are unread.
protocol MessageRepository: Sendable {
    func threads() -> [ChatThread]
    func conversations() -> [String: [Message]]
    func unreadThreadIDs() -> Set<String>
}
