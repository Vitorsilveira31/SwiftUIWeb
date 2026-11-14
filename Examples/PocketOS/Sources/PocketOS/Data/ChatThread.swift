struct ChatThread: Identifiable, Hashable, Sendable {
    static let assistantID = "pocket"

    let id: String
    let name: String
    let initials: String
    let isAssistant: Bool
    let time: String
}
