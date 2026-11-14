import SwiftUI

/// The horizontal strip. The eager branch lays out the first 2,000 cards in a
/// plain HStack; the virtualized branch builds only the cards near the port.
struct CardStripView: View {
    let viewModel: CardsViewModel

    private var stripPosition: Binding<String?> {
        Binding(
            get: { viewModel.state.stripPosition },
            set: { viewModel.send(.stripScrolled($0)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.state.eager {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.state.eagerCards) { card in
                            CardView(card: card, identifier: "card-\(card.n)")
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.trailing, 8)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollPosition(id: stripPosition)
                .frame(height: 132)
                .accessibilityIdentifier("strip")
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(viewModel.state.cards) { card in
                            CardView(card: card, identifier: "card-\(card.n)")
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.trailing, 8)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollPosition(id: stripPosition)
                .frame(height: 132)
                .accessibilityIdentifier("strip")
            }

            Text(Strings.Cards.stripFootnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(12)

            Spacer(minLength: 0)
        }
    }
}
