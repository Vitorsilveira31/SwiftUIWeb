import SwiftUI

// One message. Mine is filled in the scheme's ink; theirs is grey. The assistant's reply
// ends in an orange caret while it is still streaming.
struct Bubble: View {
    let message: Message
    @Environment(\.readingScale) private var scale

    private var isMine: Bool {
        message.role == .me
    }

    private var label: String {
        if !message.body.isEmpty { return message.body }
        return message.isStreaming ? Strings.Messages.thinking : Strings.Messages.stopped
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isMine {
                Spacer(minLength: 56)
            }
            HStack(alignment: .bottom, spacing: 3) {
                Text(label)
                    .font(Voice.text(17 * scale))
                    .lineSpacing(2)
                    .foregroundStyle(isMine ? AnyShapeStyle(BackgroundStyle()) : AnyShapeStyle(Color.primary))
                if message.isStreaming {
                    PhaseAnimator([1.0, 0.15]) { opacity in
                        Capsule()
                            .fill(Color.orange)
                            .frame(width: 3, height: 17 * scale)
                            .opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 0.45)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isMine ? Color.primary : Color.gray.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if !isMine {
                Spacer(minLength: 56)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("bubble-\(message.id)")
    }
}
