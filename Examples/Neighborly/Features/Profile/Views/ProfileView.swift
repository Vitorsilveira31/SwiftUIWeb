import SwiftUIWeb

/// A profile: the cover picture, the person, and their friends; a friend's tap opens their profile.
struct ProfileView: View {
  let viewModel: ProfileViewModel
  let openPerson: @MainActor @Sendable (Int) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let profile = viewModel.profile, viewModel.state == .loaded {
          ProfileCover(profile: profile)
          ProfileHeader(profile: profile)
          ProfileFriends(friends: profile.friends, openPerson: openPerson)
        } else {
          NeighborlyStatusView(state: viewModel.state, loading: ProfileStrings.loading, failedTitle: ProfileStrings.failedTitle, retry: ProfileStrings.retry) {
            Task { await viewModel.load() }
          }
        }
      }
      .padding(.bottom, 20)
      .frame(maxWidth: NeighborlyLayout.contentWidth)
      .frame(maxWidth: .infinity)
    }
  }
}
