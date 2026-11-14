import SwiftUIWeb

/// The wide picture across the top of a profile.
struct ProfileCover: View {
  let profile: NeighborlyProfile

  var body: some View {
    Image(profile.coverURL, alt: profile.user.name)
      .resizable()
      .scaledToFill()
      .frame(maxWidth: .infinity)
      .aspectRatio(3, contentMode: .fit)
      .clipped()
  }
}
