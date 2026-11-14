import SwiftUI

/// "It's a match!", shown over the deck until the user keeps swiping. The backdrop is opaque from its first frame;
/// only its contents wait a moment.
struct MatchOverlay: View {
    let profile: Profile
    let onKeepSwiping: () -> Void
    @State private var entered = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.75, green: 0.09, blue: 0.35),
                Color(red: 0.72, green: 0.20, blue: 0.26),
                Color(red: 0.65, green: 0.29, blue: 0.14),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .opacity(0.94)
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Text(Strings.Match.title)
                    .font(.system(size: 44, weight: .black))
                    .italic()
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("match-title")
                Text(Strings.Match.likesYou(profile.name))
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
                Portrait(profile: profile, variant: 0, emblemSize: 80)
                    .frame(width: 168, height: 168)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 5))
                    .shadow(color: .black.opacity(0.25), radius: 15, y: 12)
                    .accessibilityLabel(Strings.Card.photoOf(profile.name))
                    .accessibilityIdentifier("match-photo")
                Button(action: onKeepSwiping) {
                    Text(Strings.Match.keepSwiping)
                        .font(.system(size: 17, weight: .bold))
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .overlay(Capsule().stroke(Color.white, lineWidth: 2))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("keep-swiping")
            }
            .foregroundStyle(.white)
            .padding(32)
            .scaleEffect(entered ? 1 : 0.85)
            .opacity(entered ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.42, bounce: 0.2).delay(0.32)) {
                    entered = true
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("match-overlay")
    }
}
