import SwiftUI

// One thread in the inbox: an unread dot, the avatar, the name, the time and a preview line.
struct InboxRow: View {
    let thread: ChatThread
    let isUnread: Bool
    let preview: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(isUnread ? Color.orange : Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 8)
                Avatar(initials: thread.initials, isAssistant: thread.isAssistant, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(thread.name)
                            .font(Voice.title(17))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(thread.time)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Text(preview)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("thread-\(thread.id)")
    }
}
