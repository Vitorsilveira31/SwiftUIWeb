/// The two feeds of the timeline: posts for the reader, and posts from the people they follow.
enum QuillFeed: CaseIterable, Hashable, Sendable {
  case forYou
  case following
}
