import SwiftUIWeb

/// The stays that match: the status while they load or when they could not, the empty state, or the cards.
struct ResultsList: View {
  let viewModel: ResultsViewModel
  let session: StaySession
  let open: @MainActor @Sendable (Stay) -> Void

  var body: some View {
    if viewModel.state != .loaded {
      StaylyStatusView(state: viewModel.state, loading: ResultsStrings.loading, failedTitle: ResultsStrings.failedTitle, retry: ResultsStrings.retry) {
        Task { await viewModel.load() }
      }
    } else if viewModel.visible.isEmpty {
      Text(ResultsStrings.noMatches).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 48)
    } else {
      VStack(alignment: .leading, spacing: 16) {
        Text(ResultsStrings.found(viewModel.visible.count)).font(.caption).foregroundStyle(.secondary)
        ForEach(viewModel.visible) { stay in
          StayCard(
            stay: stay,
            nights: viewModel.query.nights,
            isFavorite: session.isFavorite(stay),
            open: { open(stay) },
            toggleFavorite: { session.toggleFavorite(stay) }
          )
        }
      }
    }
  }
}
