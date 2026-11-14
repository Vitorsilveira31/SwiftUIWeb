import SwiftUI

/// A verdict label (LIKE, NOPE, SUPER LIKE) with a coloured frame. It sits on a dark ground so its colour stays
/// readable over a bright portrait.
struct Stamp: View {
    let label: String
    let color: Color
    let tilt: Double
    let amount: Double
    let identifier: String
    let isSuper: Bool

    var body: some View {
        Text(label)
            .font(.system(size: isSuper ? 30 : 38, weight: .black))
            .tracking(2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(color)
            .frame(width: isSuper ? 200 : 138)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(tilt))
            .opacity(amount)
            .allowsHitTesting(false)
            .accessibilityIdentifier(identifier)
    }
}
