import SwiftUIWeb

/// Explore: a search and a grid of pictures, a page at a time.
struct ExploreView: View {
  let viewModel: ExploreViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        TextField(ExploreStrings.searchPrompt, text: Binding(get: { viewModel.query }, set: { viewModel.query = $0 }))
          .textFieldStyle(.roundedBorder)
          .onSubmit { Task { await viewModel.search() } }
          .padding(.horizontal, 12)
        if viewModel.state != .loaded {
          LumioStatusView(state: viewModel.state, loading: ExploreStrings.loading, failedTitle: ExploreStrings.failedTitle, retry: ExploreStrings.retry) {
            Task { await viewModel.search() }
          }
        } else if viewModel.tiles.isEmpty {
          Text(ExploreStrings.empty).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 48)
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: LumioLayout.gridSpacing)], spacing: LumioLayout.gridSpacing) {
            ForEach(viewModel.tiles) { tile in ExploreTile(tile: tile) }
          }
          ExploreFooter(viewModel: viewModel)
        }
      }
      .padding(.vertical, 12)
      .frame(maxWidth: LumioLayout.exploreWidth)
      .frame(maxWidth: .infinity)
    }
    .task { if viewModel.tiles.isEmpty { await viewModel.search() } }
  }
}
