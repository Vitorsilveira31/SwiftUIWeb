import Foundation

// A local stand-in for a language model. It picks a scripted answer and yields it word
// by word, so streaming, Stop and cancellation run with no network at all.
struct ScriptedAssistantRepository: AssistantRepository {
    static let scripted: [String] = [
        "Short answer: yes. The clock gets the loudest type on purpose, and everything else stays quiet so that it can.",
        "I can help with the phone itself, with the articles in Reader, and with most questions that fit in a text. I can’t set alarms or send messages for you.",
        "There are three voices here: the rounded face for the clock, the serif for titles and names, and the system sans for anything you read.",
        "My advice is one thing per screen, said clearly, and then getting out of the way.",
    ]

    static let noKeyReply = "There is no key saved yet, so this is only a script. Add one in Settings and this thread is ready for a real model."

    func reply(to prompt: String, hasKey: Bool, pace: Duration) -> AsyncStream<String> {
        let text = hasKey ? Self.scripted[prompt.count % Self.scripted.count] : Self.noKeyReply
        let words = text.split(separator: " ").map { "\($0) " }
        return AsyncStream { continuation in
            let producer = Task {
                for word in words {
                    do {
                        try await Task.sleep(for: pace)
                    } catch {
                        break
                    }
                    continuation.yield(word)
                }
                continuation.finish()
            }
            // The consumer going away (Stop, or a new question) cancels the producer.
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}
