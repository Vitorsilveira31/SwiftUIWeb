protocol PublishPostUseCase: Sendable {
  func execute(text: String) async throws -> QuillPost
}

struct DefaultPublishPostUseCase: PublishPostUseCase {
  let repository: any TimelineRepository

  func execute(text: String) async throws -> QuillPost { try await repository.publish(text: text) }
}
