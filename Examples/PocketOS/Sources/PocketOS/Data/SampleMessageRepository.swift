// Sample threads and conversations. The first message of the assistant thread is its introduction.
struct SampleMessageRepository: MessageRepository {
    func threads() -> [ChatThread] {
        [
            ChatThread(id: ChatThread.assistantID, name: "Pocket", initials: "P", isAssistant: true, time: "now"),
            ChatThread(id: "nico", name: "Nico", initials: "N", isAssistant: false, time: "9:12 AM"),
            ChatThread(id: "studio", name: "Studio Crew", initials: "SC", isAssistant: false, time: "8:47 AM"),
            ChatThread(id: "builds", name: "Build Bot", initials: "BB", isAssistant: false, time: "Yesterday"),
            ChatThread(id: "mom", name: "Mom", initials: "M", isAssistant: false, time: "Saturday"),
        ]
    }

    func unreadThreadIDs() -> Set<String> {
        ["nico", "studio"]
    }

    func conversations() -> [String: [Message]] {
        [
            ChatThread.assistantID: [
                line("pocket", 1, .assistant, "Pocket", "Hi, I’m Pocket. I live in this phone. Ask me anything, or hand me an article from Reader. For now I answer from a script, so you can watch a reply arrive word by word.", "9:41 AM"),
            ],
            "nico": [
                line("nico", 1, .them, "Nico", "Got the new rounded clock onto the test phone.", "8:31 AM"),
                line("nico", 2, .them, "Nico", "At full size it reads from across the room. Almost too loud.", "8:32 AM"),
                line("nico", 3, .me, "Me", "That was the point. One loud thing, then quiet.", "8:40 AM"),
                line("nico", 4, .them, "Nico", "Can you push the build to the spare phone tonight? I want to check the lock screen.", "9:12 AM"),
            ],
            "studio": [
                line("studio", 1, .them, "Ana", "Type sizes are in the branch. The rounded face finally has a proper bold.", "8:20 AM"),
                line("studio", 2, .them, "Theo", "The serif headings work next to the sans body. Three voices, no arguing.", "8:31 AM"),
                line("studio", 3, .them, "Ana", "The lowercase g in the serif still looks heavy to me.", "8:47 AM"),
                line("studio", 4, .me, "Me", "Ship it as is. We tune it once we see it on the lock screen.", "8:52 AM"),
            ],
            "builds": [
                line("builds", 1, .them, "Build Bot", "Nightly run passed: 3 of 3 device checks, lock screen snapshot attached.", "11:20 PM"),
                line("builds", 2, .them, "Build Bot", "Next: prepare the Reader build with the new articles.", "11:21 PM"),
            ],
            "mom": [
                line("mom", 1, .them, "Mom", "Did you eat?", "6:02 PM"),
                line("mom", 2, .me, "Me", "Yes, pasta.", "6:15 PM"),
                line("mom", 3, .them, "Mom", "Good. Call me when you land.", "6:16 PM"),
            ],
        ]
    }

    private func line(_ thread: String, _ number: Int, _ role: Message.Role, _ sender: String, _ body: String, _ time: String) -> Message {
        Message(id: "\(thread)-\(number)", role: role, sender: sender, body: body, time: time)
    }
}
