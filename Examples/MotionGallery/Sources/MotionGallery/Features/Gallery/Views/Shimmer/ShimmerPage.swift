import SwiftUI

/// The feed loading skeleton: twelve rows whose bars are swept by a highlight, forever.
struct ShimmerPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<12, id: \.self) { _ in
                ShimmerRow()
            }
        }
        .accessibilityIdentifier("skeleton")
    }
}
