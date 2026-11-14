import SwiftUI

/// The market list: one row per coin, with a chart that draws in on appear.
struct MarketsView: View {
    @State private var viewModel = MarketsViewModel()

    var body: some View {
        List(viewModel.state.coins) { coin in
            CoinRow(coin: coin, frozen: viewModel.state.frozen)
        }
        .listStyle(.plain)
        .accessibilityIdentifier("rows")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(Strings.Markets.tick) { viewModel.send(.tick) }
                    .accessibilityIdentifier("tick")
                Button(viewModel.state.frozen ? Strings.Markets.run : Strings.Markets.freeze) {
                    viewModel.send(.toggleFreeze)
                }
                .accessibilityIdentifier("freeze")
            }
        }
    }
}
