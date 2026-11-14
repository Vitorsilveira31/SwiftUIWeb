import SwiftUIWeb

/// A person: picture, name, where they live, what they do, and how much they have.
struct ProfileHeader: View {
  let profile: NeighborlyProfile

  var body: some View {
    HStack(alignment: .center, spacing: 20) {
      NeighborlyAvatar(user: profile.user, size: 112, ring: true)
      VStack(alignment: .leading, spacing: 6) {
        Text(profile.user.name).font(.title2).fontWeight(.bold)
        Text(ProfileStrings.from(profile.user.city)).foregroundStyle(.secondary)
        Text(profile.user.bio)
        HStack(spacing: 20) {
          ProfileStat(count: profile.postCount, label: ProfileStrings.posts)
          ProfileStat(count: profile.albumCount, label: ProfileStrings.albums)
          ProfileStat(count: profile.friends.count, label: ProfileStrings.friends)
        }
      }
    }
    .padding(.horizontal, 16)
  }
}
