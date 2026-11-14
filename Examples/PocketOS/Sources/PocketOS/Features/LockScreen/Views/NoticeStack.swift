import SwiftUI

// The notification cards and the Clear control under them. Opening a card unlocks the
// phone and goes to what the card is about.
struct NoticeStack: View {
    let lock: LockScreenViewModel
    let shell: ShellViewModel

    var body: some View {
        VStack(spacing: 10) {
            ForEach(lock.state.notices) { notice in
                NoticeCard(notice: notice) {
                    shell.send(.openNotice(notice))
                }
            }
            if !lock.state.notices.isEmpty {
                Button(Strings.Lock.clear) {
                    lock.send(.clearNotices)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(.white.opacity(0.11), in: Capsule())
                .accessibilityIdentifier("clear-notices")
            }
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("notice-stack")
    }
}
