import SwiftUIWeb

/// The results of a search. Wide screens keep the filters beside the list; a phone opens them in a sheet.
struct ResultsView: View {
  let viewModel: ResultsViewModel
  let session: StaySession
  let back: @MainActor @Sendable () -> Void
  let open: @MainActor @Sendable (Stay) -> Void
  @State private var showFilters = false

  var body: some View {
    ScrollView {
      GeometryReader { proxy in
        ResultsLayout(
          viewModel: viewModel,
          session: session,
          wide: proxy.size.width > StaylyLayout.compactWidth,
          showFilters: $showFilters,
          back: back,
          open: open
        )
      }
    }
    .task { if viewModel.state != .loaded { await viewModel.load() } }
    .sheet(isPresented: $showFilters) {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          FilterPanel(viewModel: viewModel)
          Button(ResultsStrings.showStays) { showFilters = false }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
      }
    }
  }
}
