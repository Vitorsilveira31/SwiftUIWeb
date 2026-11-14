import SwiftUI

/// One card: a fixed-size coloured tile with its label at the bottom.
struct CardView: View {
    let card: CardVO
    let identifier: String

    var body: some View {
        Text(Strings.Cards.card(card.n))
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(10)
            .frame(width: card.width, height: 116)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(CardPalette.color(card.hue))
            )
            .accessibilityIdentifier(identifier)
    }
}
