struct Message: Identifiable, Hashable, Sendable {
    enum Role: Sendable, Hashable { case me, them, assistant }

    let id: String
    let role: Role
    let sender: String
    var body: String
    let time: String
    var isStreaming = false
}
