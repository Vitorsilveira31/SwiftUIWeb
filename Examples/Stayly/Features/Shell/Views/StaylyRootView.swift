import SwiftUIWeb

/// Stayly: the brand on top, Explore, Saved and My trips as tabs. The root owns every model, so each tab keeps its state while the
/// reader moves between the tabs and between the screens of a tab; the session (saved stays and reservations) is shared.
struct StaylyRootView: View {
  @State private var tab = StaylyTab.explore
  @State private var session: StaySession
  @State private var explore: ExploreFlow
  @State private var saved: SavedViewModel
  @State private var trips: TripsViewModel

  init(dependencies: StaylyDependencies) {
    let session = StaySession()
    _session = State(wrappedValue: session)
    _explore = State(wrappedValue: ExploreFlow(dependencies: dependencies, session: session))
    _saved = State(wrappedValue: SavedViewModel(dependencies: dependencies, session: session))
    _trips = State(wrappedValue: TripsViewModel(session: session))
  }

  var body: some View {
    VStack(spacing: 0) {
      StaylyTopBar()
      Divider()
      TabView(selection: $tab) {
        ExploreView(flow: explore, session: session)
          .tabItem { Label(ShellStrings.explore, systemImage: "magnifyingglass") }.tag(StaylyTab.explore)
        SavedView(viewModel: saved, session: session)
          .tabItem { Label(ShellStrings.saved, systemImage: "heart") }.tag(StaylyTab.saved)
        TripsView(viewModel: trips)
          .tabItem { Label(ShellStrings.trips, systemImage: "suitcase") }.tag(StaylyTab.trips)
      }
      .tabViewStyle(.sidebarAdaptable)
    }
  }
}
