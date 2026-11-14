extension Strings {
    enum Messages {
        static let title = "Messages"
        static let pinned = "Pinned"
        static let recent = "Recent"
        static let askPlaceholder = "Ask Pocket"
        static let messagePlaceholder = "Message"
        static let clear = "Clear"
        static let introNote = "Pinned. Answers come from a script in this demo."
        static let addKey = "Add a key in Settings"
        static let stop = "Stop"
        static let send = "Send"
        static let thinking = "Thinking"
        static let stopped = "Stopped"
        static let sayHello = "Say hello"
        static let ellipsis = "…"
        static let me = "Me"
        static let assistantName = "Pocket"

        static func youPreview(_ body: String) -> String {
            "You: \(body)"
        }

        static func askAbout(_ title: String) -> String {
            "What do you make of “\(title)”?"
        }
    }
}
