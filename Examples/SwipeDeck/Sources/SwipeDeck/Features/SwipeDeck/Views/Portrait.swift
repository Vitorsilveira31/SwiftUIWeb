import SwiftUI

/// A profile picture drawn in code: a gradient with an initial (variant 0, 2, ...) or a person symbol (variant 1, 3, ...).
struct Portrait: View {
    let profile: Profile
    let variant: Int
    let emblemSize: CGFloat

    private static var palettes: [[Color]] {
        [
            [Color(red: 0.99, green: 0.16, blue: 0.48), Color(red: 1.0, green: 0.47, blue: 0.33)],
            [.indigo, .purple],
            [.teal, .blue],
            [.orange, .pink],
            [.mint, .green],
            [.brown, .orange],
        ]
    }

    var body: some View {
        let palette = Self.palettes
        let colors = palette[(profile.n * Profile.photoCount + variant) % palette.count]
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if variant.isMultiple(of: 2) {
                Text(profile.initial)
                    .font(.system(size: emblemSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: emblemSize))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
