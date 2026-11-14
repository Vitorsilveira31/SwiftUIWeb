import Foundation
import Observation

// Conversations, unread threads and the assistant's streaming reply. At most one answer
// streams at a time; starting another or pressing Stop cancels the one in flight.
@MainActor
@Observable
final class MessagesViewModel {
    struct State {
        var threads: [ChatThread] = []
        var conversations: [String: [Message]] = [:]
        var unread: Set<String> = []
        var isAnswering = false
    }

    enum Action {
        case load
        case markRead(String)
        case send(String, to: String, hasKey: Bool, model: ChatModel)
        case askAboutArticle(String, hasKey: Bool, model: ChatModel)
        case stop
        case clearAssistant
    }

    private(set) var state: State
    private let messageRepository: any MessageRepository
    private let assistantRepository: any AssistantRepository
    private var answerID: String?
    private var answerTask: Task<Void, Never>?
    private var serial = 0

    init(
        initialState: State = .init(),
        messageRepository: any MessageRepository = SampleMessageRepository(),
        assistantRepository: any AssistantRepository = ScriptedAssistantRepository()
    ) {
        self.state = initialState
        self.messageRepository = messageRepository
        self.assistantRepository = assistantRepository
        send(.load)
    }

    func preview(_ threadID: String) -> String {
        guard let last = state.conversations[threadID]?.last else { return Strings.Messages.sayHello }
        let body = last.body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if last.role == .me { return Strings.Messages.youPreview(body) }
        return body.isEmpty ? Strings.Messages.ellipsis : body
    }

    func send(_ action: Action) {
        switch action {
        case .load:
            state.threads = messageRepository.threads()
            state.conversations = messageRepository.conversations()
            state.unread = messageRepository.unreadThreadIDs()
        case .markRead(let id):
            state.unread.remove(id)
        case .send(let text, let threadID, let hasKey, let model):
            if threadID == ChatThread.assistantID {
                ask(text, hasKey: hasKey, model: model)
            } else {
                appendMine(text, to: threadID)
            }
        case .askAboutArticle(let title, let hasKey, let model):
            ask(Strings.Messages.askAbout(title), hasKey: hasKey, model: model)
        case .stop:
            stopAnswer()
        case .clearAssistant:
            stopAnswer()
            let seed = messageRepository.conversations()[ChatThread.assistantID] ?? []
            state.conversations[ChatThread.assistantID] = Array(seed.prefix(1))
        }
    }

    private func appendMine(_ text: String, to threadID: String) {
        serial += 1
        state.conversations[threadID, default: []].append(
            Message(id: "you-\(serial)", role: .me, sender: Strings.Messages.me, body: text, time: Self.clock)
        )
    }

    // One turn: the question is appended, then a reply bubble fills word by word as the
    // stream yields. The consuming task is kept so Stop can cancel it.
    private func ask(_ text: String, hasKey: Bool, model: ChatModel) {
        stopAnswer()
        serial += 2
        let replyID = "reply-\(serial)"
        state.conversations[ChatThread.assistantID, default: []] += [
            Message(id: "you-\(serial - 1)", role: .me, sender: Strings.Messages.me, body: text, time: Self.clock),
            Message(id: replyID, role: .assistant, sender: Strings.Messages.assistantName, body: "", time: Self.clock, isStreaming: true),
        ]
        answerID = replyID
        state.isAnswering = true
        let stream = assistantRepository.reply(to: text, hasKey: hasKey, pace: model.pace)
        answerTask = Task { [weak self] in
            for await piece in stream {
                self?.addPiece(piece, to: replyID)
            }
            self?.finishAnswer(replyID)
        }
    }

    private func stopAnswer() {
        answerTask?.cancel()
        answerTask = nil
        if let id = answerID {
            finishAnswer(id)
        }
    }

    // Guarded by the id so a cancelled task that finishes late cannot end a newer answer.
    private func finishAnswer(_ id: String) {
        guard answerID == id else { return }
        answerID = nil
        state.isAnswering = false
        if let index = assistantIndex(id) {
            state.conversations[ChatThread.assistantID]?[index].isStreaming = false
        }
    }

    private func addPiece(_ piece: String, to id: String) {
        guard let index = assistantIndex(id) else { return }
        state.conversations[ChatThread.assistantID]?[index].body += piece
    }

    private func assistantIndex(_ id: String) -> Int? {
        state.conversations[ChatThread.assistantID]?.firstIndex { $0.id == id }
    }

    private static var clock: String {
        Date.now.formatted(date: .omitted, time: .shortened)
    }
}
