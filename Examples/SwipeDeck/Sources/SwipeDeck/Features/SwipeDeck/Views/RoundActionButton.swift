import SwiftUI

/// A round button with a coloured SF Symbol, dimmed when it has nothing to act on.
struct RoundActionButton: View {
    let identifier: String
    let label: String
    let symbol: String
    let size: CGFloat
    let glyph: CGFloat
    let color: Color
    let isOff: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.gray.opacity(0.12)))
                .shadow(color: .black.opacity(0.12), radius: 9, y: 6)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(isOff)
        .opacity(isOff ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: isOff)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
