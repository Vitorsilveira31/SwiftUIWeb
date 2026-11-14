import SwiftUIWeb

/// The people to follow, each with the button that follows them.
struct WhoToFollowCard: View {
  let viewModel: SidebarViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(SidebarStrings.whoToFollow).font(.title3).fontWeight(.bold).padding(12)
      ForEach(viewModel.people) { user in
        FollowRow(user: user, viewModel: viewModel)
      }
    }
    .background(Color.secondary.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }
}
