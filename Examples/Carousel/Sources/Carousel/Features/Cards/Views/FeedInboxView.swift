import SwiftUI

/// A fixed-height vertical inbox inside a feed row.
struct FeedInboxView: View {
    let post: PostVO
    let virtual: Bool

    var body: some View {
        ScrollView(.vertical) {
            if virtual {
                LazyVStack(spacing: 0) {
                    ForEach(post.cards) { message in
                        MessageRowView(post: post.n, message: message)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(post.cards) { message in
                        MessageRowView(post: post.n, message: message)
                    }
                }
            }
        }
        .frame(height: 300)
        .accessibilityIdentifier("inbox-\(post.n)")
    }
}
