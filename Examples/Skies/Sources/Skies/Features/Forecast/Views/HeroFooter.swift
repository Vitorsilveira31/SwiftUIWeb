import SwiftUI

// The one-sentence summary of the hour, and the way back to the current conditions.
struct HeroFooter: View {
    let summary: String
    let isNow: Bool
    let onBackToNow: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Text(summary)
                .font(.footnote)
                .frame(maxWidth: 260, alignment: .leading)
                .accessibilityIdentifier("summary")
            Spacer(minLength: 0)
            if !isNow {
                Button(action: onBackToNow) {
                    Text(Strings.Forecast.backToNow)
                        .font(.caption.weight(.semibold))
                        .padding(10)
                        .background(Capsule().fill(.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("back-now")
            }
        }
    }
}
