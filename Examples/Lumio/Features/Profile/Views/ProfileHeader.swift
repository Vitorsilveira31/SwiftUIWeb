import SwiftUIWeb

/// A person: picture, name, how much they have, who they are.
struct ProfileHeader: View {
  let profile: LumioProfile

  var body: some View {
    HStack(alignment: .top, spacing: 24) {
      LumioAvatar(user: profile.user, size: 96, ring: true)
      VStack(alignment: .leading, spacing: 8) {
        Text(profile.user.username).font(.title2).fontWeight(.semibold)
        HStack(spacing: 20) {
          ProfileStat(count: profile.postCount, label: ProfileStrings.posts)
          ProfileStat(count: profile.albumTitles.count, label: ProfileStrings.albums)
          ProfileStat(count: profile.tiles.count, label: ProfileStrings.pictures)
        }
        Text(profile.user.name).fontWeight(.semibold)
        Text(profile.user.bio)
        Text(ProfileStrings.from(profile.user.city)).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
  }
}
