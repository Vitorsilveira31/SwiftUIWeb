import SwiftUI

/// One bar per photo of a card; the shown photo is bright.
struct PhotoPips: View {
    let count: Int
    let current: Int
    let identifier: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == current ? 1 : 0.4))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .accessibilityIdentifier(identifier)
    }
}
