import SwiftUIWeb

/// The people with something new, side by side, scrolling sideways.
struct StoriesRow: View {
  let people: [LumioUser]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 14) {
        ForEach(people) { user in StoryBubble(user: user) }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
    }
  }
}
