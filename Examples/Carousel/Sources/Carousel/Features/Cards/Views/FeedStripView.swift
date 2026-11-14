import SwiftUI

/// A horizontal strip inside a feed row.
struct FeedStripView: View {
    let post: PostVO
    let virtual: Bool

    var body: some View {
        ScrollView(.horizontal) {
            if virtual {
                LazyHStack(spacing: 8) {
                    ForEach(post.cards) { card in
                        CardView(card: card, identifier: "card-\(post.n)-\(card.n)")
                    }
                }
                .padding(.vertical, 8)
                .padding(.trailing, 8)
            } else {
                HStack(spacing: 8) {
                    ForEach(post.cards) { card in
                        CardView(card: card, identifier: "card-\(post.n)-\(card.n)")
                    }
                }
                .padding(.vertical, 8)
                .padding(.trailing, 8)
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 132)
        .accessibilityIdentifier("strip-\(post.n)")
    }
}
