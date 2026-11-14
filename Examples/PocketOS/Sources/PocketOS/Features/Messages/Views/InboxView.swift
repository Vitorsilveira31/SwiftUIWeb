import SwiftUI

// The inbox: the pinned assistant first, then the other threads. Each row opens its thread.
struct InboxView: View {
    let messages: MessagesViewModel
    let shell: ShellViewModel

    private var pinned: [ChatThread] {
        messages.state.threads.filter(\.isAssistant)
    }

    private var recent: [ChatThread] {
        messages.state.threads.filter { !$0.isAssistant }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Strings.Messages.title)
                .font(Voice.title(34))
                .padding(.horizontal, 16)
                .padding(.top, 4)
            List {
                Section(Strings.Messages.pinned) {
                    ForEach(pinned) { thread in
                        row(thread)
                    }
                }
                Section(Strings.Messages.recent) {
                    ForEach(recent) { thread in
                        row(thread)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("messages-list")
        }
    }

    private func row(_ thread: ChatThread) -> InboxRow {
        InboxRow(
            thread: thread,
            isUnread: messages.state.unread.contains(thread.id),
            preview: messages.preview(thread.id)
        ) {
            shell.send(.openThread(thread.id))
        }
    }
}
