import SwiftUIWeb

/// The saved stays. A card opens the stay's page, and its heart takes the stay off the list.
struct SavedView: View {
  let viewModel: SavedViewModel
  let session: StaySession

  var body: some View {
    if let detail = viewModel.detail {
      DetailView(viewModel: detail) { viewModel.closeDetail() }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(SavedStrings.title).font(.title2).fontWeight(.bold)
          if viewModel.state != .loaded {
            StaylyStatusView(state: viewModel.state, loading: SavedStrings.loading, failedTitle: SavedStrings.failedTitle, retry: SavedStrings.retry) {
              Task { await viewModel.load() }
            }
          } else if viewModel.saved.isEmpty {
            Text(SavedStrings.empty).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 48)
          } else {
            ForEach(viewModel.saved) { stay in
              StayCard(
                stay: stay,
                isFavorite: session.isFavorite(stay),
                open: { viewModel.open(stay) },
                toggleFavorite: { session.toggleFavorite(stay) }
              )
            }
          }
        }
        .padding(20)
        .frame(maxWidth: StaylyLayout.resultsWidth)
        .frame(maxWidth: .infinity)
      }
      .task { if viewModel.state != .loaded { await viewModel.load() } }
    }
  }
}
