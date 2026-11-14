/// Where the timeline and the posts people write come from.
protocol TimelineRepository: Sendable {
  /// A page of a feed. The Following feed is one page: the posts of the people it follows.
  func posts(feed: QuillFeed, page: Int) async throws -> [QuillPost]
  /// Posts what the reader wrote; the service answers with the post and its new id.
  func publish(text: String) async throws -> QuillPost
}
