import SwiftUIWeb

/// The header, then either the filters beside the list (wide) or the list alone (a phone, where the filters are in a sheet).
struct ResultsLayout: View {
  let viewModel: ResultsViewModel
  let session: StaySession
  let wide: Bool
  let showFilters: Binding<Bool>
  let back: @MainActor @Sendable () -> Void
  let open: @MainActor @Sendable (Stay) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ResultsHeader(viewModel: viewModel, showsFilters: !wide, back: back) { showFilters.wrappedValue = true }
      if wide {
        HStack(alignment: .top, spacing: 24) {
          FilterPanel(viewModel: viewModel).frame(width: StaylyLayout.filterWidth)
          ResultsList(viewModel: viewModel, session: session, open: open)
        }
      } else {
        ResultsList(viewModel: viewModel, session: session, open: open)
      }
    }
    .padding(20)
    .frame(maxWidth: StaylyLayout.resultsWidth)
    .frame(maxWidth: .infinity)
  }
}
