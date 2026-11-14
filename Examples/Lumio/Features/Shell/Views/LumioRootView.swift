import SwiftUIWeb

/// Lumio: the brand on top, Home, Explore and Profile as tabs.
struct LumioRootView: View {
  @State private var tab = LumioTab.home
  @State private var feed: FeedViewModel
  @State private var explore: ExploreViewModel
  @State private var profile: ProfileViewModel

  init(dependencies: LumioDependencies) {
    _feed = State(wrappedValue: FeedViewModel(loadFeed: dependencies.loadFeed, loadStories: dependencies.loadStories, loadComments: dependencies.loadComments, addComment: dependencies.addComment))
    _explore = State(wrappedValue: ExploreViewModel(load: dependencies.loadExplore))
    _profile = State(wrappedValue: ProfileViewModel(userID: dependencies.currentUserID, load: dependencies.loadProfile))
  }

  var body: some View {
    VStack(spacing: 0) {
      LumioTopBar()
      Divider()
      TabView(selection: $tab) {
        FeedView(viewModel: feed)
          .tabItem { Label(ShellStrings.home, systemImage: "house") }.tag(LumioTab.home)
        ExploreView(viewModel: explore)
          .tabItem { Label(ShellStrings.explore, systemImage: "magnifyingglass") }.tag(LumioTab.explore)
        ProfileView(viewModel: profile)
          .tabItem { Label(ShellStrings.profile, systemImage: "person") }.tag(LumioTab.profile)
      }
      .tabViewStyle(.sidebarAdaptable)
    }
  }
}
