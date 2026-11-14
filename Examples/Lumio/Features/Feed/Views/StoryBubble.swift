import SwiftUIWeb

/// One person's story: their picture inside the brand ring, their name below.
struct StoryBubble: View {
  let user: LumioUser

  var body: some View {
    VStack(spacing: 6) {
      LumioAvatar(user: user, size: LumioLayout.storySize, ring: true)
      Text(user.username).font(.caption).lineLimit(1).frame(width: LumioLayout.storySize + 16)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(FeedStrings.storyLabel(user.name))
  }
}
