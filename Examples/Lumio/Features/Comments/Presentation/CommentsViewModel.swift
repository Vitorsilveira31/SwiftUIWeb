import SwiftUIWeb

/// A post's comments and the one being written.
@MainActor @Observable
final class CommentsViewModel {
  private(set) var comments: [LumioComment] = []
  private(set) var state: LoadState = .loading
  private(set) var sendFailed = false
  private(set) var isSending = false
  var draft = ""
  private let postID: Int
  private let load: any LoadCommentsUseCase
  private let add: any AddCommentUseCase

  init(postID: Int, load: any LoadCommentsUseCase, add: any AddCommentUseCase) {
    self.postID = postID
    self.load = load
    self.add = add
  }

  /// A comment with nothing but spaces is not worth sending.
  var canSend: Bool { draft.contains(where: { $0 != " " && $0 != "\n" }) }

  func loadComments() async {
    state = .loading
    do {
      comments = try await load.execute(postID: postID)
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
      comments.append(try await add.execute(postID: postID, text: draft))
      draft = ""
    } catch {
      sendFailed = true
    }
  }
}
