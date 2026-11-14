import SwiftUIWeb

/// A post's thread: its replies and the reply being written. It counts the replies sent here, so the timeline can show them when the thread closes.
@MainActor @Observable
final class PostDetailViewModel {
  let post: QuillPost
  private(set) var replies: [QuillReply] = []
  private(set) var state: LoadState = .loading
  private(set) var sendFailed = false
  private(set) var sentCount = 0
  var draft = ""
  private let loadReplies: any LoadRepliesUseCase
  private let addReply: any AddReplyUseCase

  init(post: QuillPost, loadReplies: any LoadRepliesUseCase, addReply: any AddReplyUseCase) {
    self.post = post
    self.loadReplies = loadReplies
    self.addReply = addReply
  }

  /// A reply with nothing but spaces is not worth sending.
  var canSend: Bool { draft.contains(where: { $0 != " " && $0 != "\n" }) }

  func load() async {
    state = .loading
    do {
      replies = try await loadReplies.execute(postID: post.id)
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  func send() async {
    guard canSend else { return }
    sendFailed = false
    do {
      let reply = try await addReply.execute(postID: post.id, text: draft)
      replies.append(reply)
      sentCount += 1
      draft = ""
    } catch {
      sendFailed = true
    }
  }
}
