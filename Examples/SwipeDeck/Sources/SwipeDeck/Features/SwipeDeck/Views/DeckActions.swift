import SwiftUI

/// The round buttons under the deck. Undo takes back the last decision; the others throw the top card.
struct DeckActions: View {
    let viewModel: SwipeDeckViewModel

    var body: some View {
        HStack(spacing: 18) {
            RoundActionButton(identifier: "btn-undo", label: Strings.Deck.undo, symbol: "arrow.uturn.backward",
                              size: 48, glyph: 20, color: .yellow,
                              isOff: viewModel.state.history.isEmpty) {
                viewModel.send(.undo)
            }
            RoundActionButton(identifier: "btn-nope", label: Strings.Deck.nope, symbol: "xmark",
                              size: 64, glyph: 28, color: .red,
                              isOff: viewModel.isExhausted) {
                viewModel.send(.throwCard(.nope, releasedY: 0))
            }
            RoundActionButton(identifier: "btn-super", label: Strings.Deck.superLike, symbol: "star.fill",
                              size: 48, glyph: 20, color: .blue,
                              isOff: viewModel.isExhausted) {
                viewModel.send(.throwCard(.superLike, releasedY: 0))
            }
            RoundActionButton(identifier: "btn-like", label: Strings.Deck.like, symbol: "heart.fill",
                              size: 64, glyph: 28, color: .green,
                              isOff: viewModel.isExhausted) {
                viewModel.send(.throwCard(.like, releasedY: 0))
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }
}
