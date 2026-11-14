import SwiftUIWeb

/// One post's comments, and the comment being written under it.
@MainActor @Observable
final class PostThreadViewModel {
  private(set) var comments: [NeighborlyComment] = []
  private(set) var state: LoadState = .loading
  private(set) var sendFailed = false
  private(set) var isSending = false
  var draft = ""
  let postID: Int
  private let loadComments: any LoadCommentsUseCase
  private let addComment: any AddCommentUseCase

  init(postID: Int, load: any LoadCommentsUseCase, add: any AddCommentUseCase) {
    self.postID = postID
    loadComments = load
    addComment = add
  }

  /// A comment with nothing but spaces is not worth sending.
  var canSend: Bool { draft.contains(where: { $0 != " " && $0 != "\n" }) }

  func load() async {
    state = .loading
    do {
      comments = try await loadComments.execute(postID: postID)
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  func send() async {
    // A second tap while the comment is on its way does nothing.
    guard canSend, !isSending else { return }
    isSending = true
    defer { isSending = false }
    sendFailed = false
    do {
      comments.append(try await addComment.execute(postID: postID, text: draft))
      draft = ""
    } catch {
      sendFailed = true
    }
  }
}
