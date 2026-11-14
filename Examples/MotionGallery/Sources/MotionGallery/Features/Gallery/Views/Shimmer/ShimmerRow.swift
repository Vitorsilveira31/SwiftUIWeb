import SwiftUI

/// A round avatar placeholder beside two text-line placeholders.
struct ShimmerRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ShimmerBar(corner: 20)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                ShimmerBar(corner: 5)
                    .frame(height: 10)
                ShimmerBar(corner: 5)
                    .frame(width: 160, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
