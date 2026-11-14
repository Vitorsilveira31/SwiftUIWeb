import SwiftUI

// A short message that rises from the bottom edge and does not take touches.
struct Toast: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityIdentifier("toast")
        }
    }
}
