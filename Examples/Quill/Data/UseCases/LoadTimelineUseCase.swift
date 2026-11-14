protocol LoadTimelineUseCase: Sendable {
  func execute(feed: QuillFeed, page: Int) async throws -> [QuillPost]
}

struct DefaultLoadTimelineUseCase: LoadTimelineUseCase {
  let repository: any TimelineRepository

  func execute(feed: QuillFeed, page: Int) async throws -> [QuillPost] { try await repository.posts(feed: feed, page: page) }
}
