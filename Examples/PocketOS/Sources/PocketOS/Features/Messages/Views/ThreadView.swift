import SwiftUI

// One conversation: the transcript, and a composer on the bottom safe-area inset so the
// keyboard lifts it. Opening the thread marks it read.
struct ThreadView: View {
    let threadID: String
    let messages: MessagesViewModel
    let shell: ShellViewModel
    @AppStorage("pocketos.assistantKey") private var assistantKey = ""
    @AppStorage("pocketos.assistantModel") private var assistantModel = ChatModel.balanced.rawValue
    @State private var scrollTarget: String?

    private var thread: ChatThread? {
        messages.state.threads.first { $0.id == threadID }
    }

    private var transcript: [Message] {
        messages.state.conversations[threadID] ?? []
    }

    private var isAssistant: Bool {
        threadID == ChatThread.assistantID
    }

    private var chatModel: ChatModel {
        ChatModel(rawValue: assistantModel) ?? .balanced
    }

    var body: some View {
        VStack(spacing: 0) {
            ThreadHeader(
                thread: thread,
                isAssistant: isAssistant,
                onBack: { shell.send(.closeThread) },
                onClear: { messages.send(.clearAssistant) }
            )
            ScrollView {
                LazyVStack(spacing: 8) {
                    if isAssistant {
                        ThreadIntro(showsAddKey: assistantKey.isEmpty) {
                            shell.send(.open(.settings))
                        }
                    }
                    ForEach(transcript) { message in
                        Bubble(message: message)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollPosition(id: $scrollTarget, anchor: .bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: transcript.count) { _, _ in
                scrollTarget = transcript.last?.id
            }
            .onChange(of: transcript.last?.body) { _, _ in
                scrollTarget = transcript.last?.id
            }
            .accessibilityIdentifier("transcript")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Composer(isAssistant: isAssistant, isAnswering: messages.state.isAnswering) { text in
                    messages.send(.send(text, to: threadID, hasKey: !assistantKey.isEmpty, model: chatModel))
                } onStop: {
                    messages.send(.stop)
                }
            }
        }
        .onAppear {
            messages.send(.markRead(threadID))
        }
    }
}
