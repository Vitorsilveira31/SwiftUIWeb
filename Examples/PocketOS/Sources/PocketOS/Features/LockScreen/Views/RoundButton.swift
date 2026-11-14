import SwiftUI

// A round control at the bottom of the lock screen: the flashlight or the camera.
struct RoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("lock-\(label.lowercased())")
    }
}
