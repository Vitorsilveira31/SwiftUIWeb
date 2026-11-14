import SwiftUI

// The message field and its button: Send, or Stop while the assistant is answering.
struct Composer: View {
    let isAssistant: Bool
    let isAnswering: Bool
    let onSend: (String) -> Void
    let onStop: () -> Void

    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @Environment(\.readingScale) private var scale

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                isAssistant ? Strings.Messages.askPlaceholder : Strings.Messages.messagePlaceholder,
                text: $draft,
                axis: .vertical
            )
            .lineLimit(1...5)
            .font(Voice.text(17 * scale))
            .focused($composerFocused)
            .onSubmit(send)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("composer")
            if isAnswering {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.3), in: Circle())
                }
                .accessibilityLabel(Strings.Messages.stop)
                .accessibilityIdentifier("stop")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.orange, in: Circle())
                }
                .disabled(trimmedDraft.isEmpty)
                .accessibilityLabel(Strings.Messages.send)
                .accessibilityIdentifier("send")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        draft = ""
        onSend(text)
        composerFocused = true
    }
}
