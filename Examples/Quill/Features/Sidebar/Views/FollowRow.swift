import SwiftUIWeb

/// One person to follow: their picture, name and handle, and the button that follows them.
struct FollowRow: View {
  let user: QuillUser
  let viewModel: SidebarViewModel

  var body: some View {
    HStack(spacing: 10) {
      QuillAvatar(url: user.avatarURL, label: user.name, size: 40)
      VStack(alignment: .leading, spacing: 0) {
        Text(user.name).fontWeight(.semibold).lineLimit(1)
        Text(user.handle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button(viewModel.isFollowing(user) ? SidebarStrings.followed : SidebarStrings.follow) { viewModel.toggleFollow(user) }
        .buttonStyle(.bordered)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}
