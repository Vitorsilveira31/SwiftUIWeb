import SwiftUI

// The thread's top bar: back to the inbox, the contact's avatar and name, and Clear for the assistant.
struct ThreadHeader: View {
    let thread: ChatThread?
    let isAssistant: Bool
    let onBack: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Label(Strings.Messages.title, systemImage: "chevron.left")
                    .font(.system(size: 17))
            }
            .accessibilityIdentifier("thread-back")
            Spacer()
            VStack(spacing: 2) {
                Avatar(initials: thread?.initials ?? "", isAssistant: isAssistant, size: 36)
                Text(thread?.name ?? "")
                    .font(Voice.title(13))
            }
            Spacer()
            Button(Strings.Messages.clear, action: onClear)
                .opacity(isAssistant ? 1 : 0)
                .disabled(!isAssistant)
                .accessibilityIdentifier("thread-clear")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
    }
}
