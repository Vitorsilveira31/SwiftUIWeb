import SwiftUI

/// Thirty-six cards in the shortest-column layout; Shuffle lays out the next deck.
struct MasonryStudyView: View {
    @State private var viewModel: MasonryViewModel

    init(repository: any TextStudiesRepository) {
        _viewModel = State(initialValue: MasonryViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: Strings.Masonry.eyebrow)
                HStack(alignment: .firstTextBaseline) {
                    Text(Strings.Masonry.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button(Strings.Masonry.shuffle) { viewModel.send(.shuffle) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("shuffle")
                }
                MasonryLayout(seed: viewModel.state.seed) {
                    ForEach(viewModel.state.cards) { card in
                        CardView(card: card)
                    }
                }
                .accessibilityIdentifier("masonry")
            }
            .padding()
        }
    }
}
