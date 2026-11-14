import SwiftUIWeb

/// The post being written: what it says, how many characters are left, and whether it is on its way.
@MainActor @Observable
final class ComposerViewModel {
  var draft = ""
  private(set) var isPosting = false
  private(set) var sendFailed = false
  private let publish: any PublishPostUseCase

  init(publish: any PublishPostUseCase) {
    self.publish = publish
  }

  var remaining: Int { QuillLayout.postLimit - draft.count }

  var isOverLimit: Bool { remaining < 0 }

  /// A post of nothing but spaces is not worth sending, and one over the limit is not allowed.
  var canPost: Bool {
    !isPosting && !isOverLimit && draft.contains(where: { $0 != " " && $0 != "\n" })
  }

  /// Sends the post. On success the draft is cleared and `posted` gets the post the service kept; on failure the draft stays.
  func post(_ posted: @MainActor @Sendable (QuillPost) -> Void) async {
    guard canPost else { return }
    isPosting = true
    sendFailed = false
    defer { isPosting = false }
    do {
      let post = try await publish.execute(text: draft)
      draft = ""
      posted(post)
    } catch {
      sendFailed = true
    }
  }
}
