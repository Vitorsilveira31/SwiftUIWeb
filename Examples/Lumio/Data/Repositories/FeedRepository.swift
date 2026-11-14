/// Where the feed and the people who post in it come from.
protocol FeedRepository: Sendable {
  func posts(page: Int) async throws -> [LumioPost]
  func people() async throws -> [LumioUser]
}
