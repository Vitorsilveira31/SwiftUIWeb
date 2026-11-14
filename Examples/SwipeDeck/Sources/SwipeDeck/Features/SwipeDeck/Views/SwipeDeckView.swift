import SwiftUI

/// The swipe deck screen: the like counter, the stack of cards, and the round action buttons.
struct SwipeDeckView: View {
    @State private var viewModel = SwipeDeckViewModel(repository: SampleProfileRepository())
    /// How far the top card has been dragged towards a decision, 0 to 1. The card under it grows with this.
    @State private var dragProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            DeckHeader(likes: viewModel.likes)
            DeckStage(viewModel: viewModel, dragProgress: $dragProgress)
            DeckActions(viewModel: viewModel)
        }
        .overlay {
            if let matched = viewModel.state.matchedIndex {
                MatchOverlay(profile: viewModel.profiles[matched]) {
                    viewModel.send(.dismissMatch)
                }
                .transition(.opacity)
            }
        }
        .accessibilityIdentifier("swipe-deck")
    }
}
