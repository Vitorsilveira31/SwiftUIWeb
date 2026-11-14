import SwiftUIWeb

/// The Explore tab: the search form, then the results of a search, then one stay's page. The buttons move between them.
struct ExploreView: View {
  let flow: ExploreFlow
  let session: StaySession

  var body: some View {
    if flow.route == .stay, let detail = flow.detail {
      DetailView(viewModel: detail) { flow.backToResults() }
    } else if flow.route == .results, let results = flow.results {
      ResultsView(viewModel: results, session: session, back: { flow.backToForm() }, open: { stay in flow.openStay(stay) })
    } else {
      SearchView(viewModel: flow.search) { flow.showResults() }
    }
  }
}
