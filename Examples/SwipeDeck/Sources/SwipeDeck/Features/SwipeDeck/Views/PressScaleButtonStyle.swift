import SwiftUI

/// Presses a control down a little while the finger is on it.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }
}
