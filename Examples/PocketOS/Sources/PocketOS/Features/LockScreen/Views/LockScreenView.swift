import SwiftUI

// The lock screen: the live clock, the notification stack and two round buttons. The whole
// screen takes the upward drag, and the stack lifts with the finger, so unlocking is the
// stack's own gesture rather than a control.
struct LockScreenView: View {
    let lock: LockScreenViewModel
    let shell: ShellViewModel
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 0) {
                LockClock()
                    .padding(.top, 40)
                Spacer(minLength: 24)
                NoticeStack(lock: lock, shell: shell)
                    .offset(y: min(0, drag))
                Spacer(minLength: 24)
                HStack {
                    RoundButton(symbol: "flashlight.on.fill", label: Strings.Lock.flashlight) {
                        shell.send(.activate(nil, name: Strings.Lock.flashlight))
                    }
                    Spacer()
                    RoundButton(symbol: "camera.fill", label: Strings.Lock.camera) {
                        shell.send(.activate(nil, name: Strings.Lock.camera))
                    }
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 14)
                Text(Strings.Lock.swipeUp)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
                Capsule()
                    .fill(.primary)
                    .frame(width: 134, height: 5)
                    .padding(.bottom, 8)
            }
        }
        .contentShape(Rectangle())
        .gesture(unlockDrag)
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("lock-screen")
    }

    // Past 120 points upward the phone unlocks; short of that the stack springs back.
    private var unlockDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                drag = value.translation.height
            }
            .onEnded { value in
                let lift = value.translation.height
                withAnimation(.smooth) {
                    drag = 0
                    if lift < -120 {
                        shell.send(.unlock)
                    }
                }
            }
    }
}
