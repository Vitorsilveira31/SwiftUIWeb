import SwiftUI

/// The area the cards are stacked in. It is sized from the stage, so the throw distances match what is drawn.
struct DeckStage: View {
    let viewModel: SwipeDeckViewModel
    @Binding var dragProgress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let layout = DeckLayout(stage: proxy.size)
            ZStack {
                ForEach(viewModel.visibleProfiles) { profile in
                    DeckCard(viewModel: viewModel, profile: profile, layout: layout, dragProgress: $dragProgress)
                }
                if viewModel.isExhausted {
                    EmptyDeckView {
                        viewModel.send(.startOver)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Thrown cards fly off the stage; clipping keeps them out of the view.
            .clipped()
        }
    }
}
