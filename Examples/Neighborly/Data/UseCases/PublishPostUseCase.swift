protocol PublishPostUseCase: Sendable {
  func execute(text: String) async throws -> NeighborlyPost
}

struct DefaultPublishPostUseCase: PublishPostUseCase {
  let repository: any FeedRepository

  func execute(text: String) async throws -> NeighborlyPost { try await repository.publish(text: text) }
}
