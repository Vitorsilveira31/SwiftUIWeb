import SwiftUI

/// 1,200 cards in the same masonry layout. Every height is known before the scroll extent is set.
struct WallStudyView: View {
    let cards: [CardVO]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: Strings.Wall.eyebrow)
                Text(Strings.Wall.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                MasonryLayout(seed: CardDeck.wallSeed) {
                    ForEach(cards) { card in
                        CardView(card: card)
                    }
                }
                .accessibilityIdentifier("wall")
            }
            .padding()
        }
    }
}
