import SwiftUIWeb

/// The feed's state: the posts a page at a time, the composer's draft, the likes, the comment threads that are open, and the group in view.
@MainActor @Observable
final class FeedViewModel {
  private(set) var posts: [NeighborlyPost] = []
  private(set) var state: LoadState = .loading
  private(set) var isLoadingMore = false
  private(set) var reachedEnd = false
  private(set) var isPublishing = false
  private(set) var publishFailed = false
  private(set) var likedIDs: Set<Int> = []
  private(set) var openThreadIDs: Set<Int> = []
  /// The city whose neighbors the feed shows (a group in the left column); nil shows everyone.
  private(set) var group: String?
  var draft = ""
  private var page = 0
  private var threads: [Int: PostThreadViewModel] = [:]
  private let loadFeed: any LoadFeedUseCase
  private let publish: any PublishPostUseCase
  private let loadComments: any LoadCommentsUseCase
  private let addComment: any AddCommentUseCase

  init(loadFeed: any LoadFeedUseCase, publish: any PublishPostUseCase, loadComments: any LoadCommentsUseCase, addComment: any AddCommentUseCase) {
    self.loadFeed = loadFeed
    self.publish = publish
    self.loadComments = loadComments
    self.addComment = addComment
  }

  /// The posts the feed shows: all of them, or those of the group's neighbors.
  var visiblePosts: [NeighborlyPost] {
    guard let group else { return posts }
    return posts.filter { $0.author.city == group }
  }

  /// A draft with nothing but spaces is not worth sharing, and a post is not sent twice.
  var canPublish: Bool { !isPublishing && draft.contains(where: { $0 != " " && $0 != "\n" }) }

  /// The first page; also what Try again runs.
  func load() async {
    state = .loading
    page = 0
    reachedEnd = false
    do {
      posts = try await loadFeed.execute(page: 1)
      page = 1
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  func loadMore() async {
    guard state == .loaded, !isLoadingMore, !reachedEnd else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let next = try await loadFeed.execute(page: page + 1)
      reachedEnd = next.isEmpty
      posts.append(contentsOf: next)
      page += 1
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  /// Shares the draft: the post goes first in the feed and the draft is cleared.
  func publishDraft() async {
    guard canPublish else { return }
    isPublishing = true
    publishFailed = false
    defer { isPublishing = false }
    do {
      posts.insert(try await publish.execute(text: draft), at: 0)
      draft = ""
    } catch {
      publishFailed = true
    }
  }

  func setGroup(_ city: String?) { group = city }

  func isLiked(_ post: NeighborlyPost) -> Bool { likedIDs.contains(post.id) }

  /// The reactions shown: the post's, plus the reader's own like.
  func reactions(of post: NeighborlyPost) -> Int { post.reactions + (isLiked(post) ? 1 : 0) }

  func toggleLike(_ post: NeighborlyPost) {
    if likedIDs.contains(post.id) { likedIDs.remove(post.id) } else { likedIDs.insert(post.id) }
  }

  func isThreadOpen(_ post: NeighborlyPost) -> Bool { openThreadIDs.contains(post.id) }

  func thread(for post: NeighborlyPost) -> PostThreadViewModel? { threads[post.id] }

  /// The comments the post shows: the ones loaded once its thread was opened, else the count it came with.
  func commentCount(of post: NeighborlyPost) -> Int {
    if let thread = threads[post.id], thread.state == .loaded { return thread.comments.count }
    return post.commentCount
  }

  /// Opens a post's comments under it (loading them the first time) or closes them.
  func toggleThread(_ post: NeighborlyPost) async {
    if openThreadIDs.contains(post.id) {
      openThreadIDs.remove(post.id)
      return
    }
    openThreadIDs.insert(post.id)
    let thread = threads[post.id] ?? PostThreadViewModel(postID: post.id, load: loadComments, add: addComment)
    threads[post.id] = thread
    if thread.state != .loaded { await thread.load() }
  }
}
