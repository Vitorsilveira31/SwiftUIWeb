import SwiftUI

/// The top bar: the flame mark and the running count of likes.
struct DeckHeader: View {
    let likes: Int

    var body: some View {
        HStack {
            Image(systemName: "flame.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.tint)
                Text("\(likes)")
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("like-count")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.gray.opacity(0.12)))
            .accessibilityIdentifier("like-counter")
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .accessibilityIdentifier("header")
    }
}
