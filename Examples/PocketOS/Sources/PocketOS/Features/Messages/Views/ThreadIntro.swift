import SwiftUI

// The assistant's introduction at the top of its thread. Without a saved key it links to Settings.
struct ThreadIntro: View {
    let showsAddKey: Bool
    let onAddKey: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Avatar(initials: "P", isAssistant: true, size: 64)
            Text(Strings.Messages.assistantName)
                .font(Voice.title(20))
            Text(Strings.Messages.introNote)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if showsAddKey {
                Button(Strings.Messages.addKey, action: onAddKey)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("thread-add-key")
            }
        }
        .padding(.bottom, 10)
    }
}
