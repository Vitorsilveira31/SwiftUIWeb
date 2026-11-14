import SwiftUIWeb

/// The search form: a title, the destination, the dates and the guests, and the button that shows the stays.
struct SearchView: View {
  let viewModel: SearchViewModel
  let search: @MainActor @Sendable () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(SearchStrings.title).font(.largeTitle).fontWeight(.bold)
        Text(SearchStrings.subtitle).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 16) {
          if viewModel.state == .loaded {
            DestinationField(viewModel: viewModel)
          } else if case .failed(let reason) = viewModel.state {
            StaylyStatusView(state: .failed(reason), loading: SearchStrings.loading, failedTitle: SearchStrings.failedTitle, retry: SearchStrings.retry) {
              Task { await viewModel.loadDestinations() }
            }
          } else {
            StaylyStatusView(state: .loading, loading: SearchStrings.loading, failedTitle: SearchStrings.failedTitle, retry: SearchStrings.retry) {}
          }
          DateFields(viewModel: viewModel)
          GuestsField(viewModel: viewModel)
          Button(SearchStrings.search, action: search)
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: StaylyLayout.cardRadius))
      }
      .padding(20)
      .frame(maxWidth: StaylyLayout.formWidth)
      .frame(maxWidth: .infinity)
    }
    .task { if viewModel.destinations.isEmpty { await viewModel.loadDestinations() } }
  }
}
