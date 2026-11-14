import SwiftUI

/// The Cards screen: a 25,000-card horizontal strip, or a vertical feed whose
/// rows hold their own strips and inboxes. Toolbar actions switch between them.
struct CardsView: View {
    @State private var viewModel = CardsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.state.page == .feed {
                FeedView(viewModel: viewModel)
            } else {
                CardStripView(viewModel: viewModel)
            }
        }
        .accessibilityIdentifier("carousel")
        .navigationTitle(Strings.Cards.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(Strings.Cards.far) { viewModel.send(.far) }
                    .accessibilityIdentifier("far")
                Button(viewModel.state.page == .feed ? Strings.Cards.strip : Strings.Cards.feed) {
                    viewModel.send(.togglePage)
                }
                .accessibilityIdentifier("feed-page")
                Button(viewModel.state.eager ? Strings.Cards.virtualized : Strings.Cards.eager) {
                    viewModel.send(.toggleEager)
                }
                .accessibilityIdentifier("eager")
            }
            if viewModel.state.page == .feed {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(Strings.Cards.down) { viewModel.send(.feedDown) }
                        .accessibilityIdentifier("feed-far")
                    Button(Strings.Cards.top) { viewModel.send(.feedTop) }
                        .accessibilityIdentifier("feed-top")
                }
            }
        }
    }
}
