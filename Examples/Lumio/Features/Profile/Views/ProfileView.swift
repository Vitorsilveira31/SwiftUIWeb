import SwiftUIWeb

/// A profile: the person, their highlights and their pictures.
struct ProfileView: View {
  let viewModel: ProfileViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if let profile = viewModel.profile, viewModel.state == .loaded {
          ProfileHeader(profile: profile)
          ProfileHighlights(titles: profile.albumTitles)
          Divider()
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: LumioLayout.gridSpacing)], spacing: LumioLayout.gridSpacing) {
            ForEach(profile.tiles) { tile in ExploreTile(tile: tile) }
          }
        } else {
          LumioStatusView(state: viewModel.state, loading: ProfileStrings.loading, failedTitle: ProfileStrings.failedTitle, retry: ProfileStrings.retry) {
            Task { await viewModel.load() }
          }
        }
      }
      .padding(.vertical, 20)
      .frame(maxWidth: LumioLayout.profileWidth)
      .frame(maxWidth: .infinity)
    }
    .task { if viewModel.profile == nil { await viewModel.load() } }
  }
}
