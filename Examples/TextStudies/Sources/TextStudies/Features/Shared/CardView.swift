import SwiftUI

/// One card of the masonry and the wall.
struct CardView: View {
    let card: CardVO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.system(size: 18, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(card.body)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(Strings.Card.footer(number: card.index + 1, words: card.words))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))
        .accessibilityIdentifier("card-\(card.index + 1)")
    }
}
