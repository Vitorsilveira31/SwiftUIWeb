import SwiftUI

/// One feed row: a header, then a strip, an inbox or a text line.
struct FeedPostView: View {
    let post: PostVO
    let virtual: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Strings.Cards.post(post.n))
                .font(.system(size: 15, weight: .semibold))
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)

            switch post.kind {
            case .strip:
                FeedStripView(post: post, virtual: virtual)
            case .inbox:
                FeedInboxView(post: post, virtual: virtual)
            case .text:
                Text(Strings.Cards.ordinaryRow)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
        }
        .accessibilityIdentifier("post-\(post.n)")
    }
}
