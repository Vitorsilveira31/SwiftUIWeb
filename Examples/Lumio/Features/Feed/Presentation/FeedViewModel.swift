import SwiftUIWeb

/// The feed's state: the people with stories, the posts a page at a time, what the reader liked and saved, and the post whose comments are open.
@MainActor @Observable
final class FeedViewModel {
  private(set) var posts: [LumioPost] = []
  private(set) var stories: [LumioUser] = []
  private(set) var state: LoadState = .loading
  private(set) var isLoadingMore = false
  private(set) var reachedEnd = false
  private(set) var likedIDs: Set<Int> = []
  private(set) var savedIDs: Set<Int> = []
  var commenting: LumioPost?
  private var page = 0
  /// Counts the loads started; a result that finishes after a newer load started is dropped.
  private var loadSerial = 0
  private let loadFeed: any LoadFeedUseCase
  private let loadStories: any LoadStoriesUseCase
  private let loadComments: any LoadCommentsUseCase
  private let addComment: any AddCommentUseCase

  init(loadFeed: any LoadFeedUseCase, loadStories: any LoadStoriesUseCase, loadComments: any LoadCommentsUseCase, addComment: any AddCommentUseCase) {
    self.loadFeed = loadFeed
    self.loadStories = loadStories
    self.loadComments = loadComments
    self.addComment = addComment
  }

  /// The first page and the stories; also what Try again runs.
  func load() async {
    loadSerial += 1
    let current = loadSerial
    state = .loading
    page = 0
    reachedEnd = false
    do {
      let loadedStories = try await loadStories.execute()
      guard current == loadSerial else { return }
      stories = loadedStories
      let loadedPosts = try await loadFeed.execute(page: 1)
      guard current == loadSerial else { return }
      posts = loadedPosts
      page = 1
      state = .loaded
    } catch {
      guard current == loadSerial else { return }
      state = .failed(FailureText.unreachable)
    }
  }

  func loadMore() async {
    guard state == .loaded, !isLoadingMore, !reachedEnd else { return }
    let current = loadSerial
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let next = try await loadFeed.execute(page: page + 1)
      guard current == loadSerial else { return }
      reachedEnd = next.isEmpty
      posts.append(contentsOf: next)
      page += 1
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  func isLiked(_ post: LumioPost) -> Bool { likedIDs.contains(post.id) }

  func isSaved(_ post: LumioPost) -> Bool { savedIDs.contains(post.id) }

  /// The likes shown: the post's, plus the reader's own.
  func likes(of post: LumioPost) -> Int { post.likes + (isLiked(post) ? 1 : 0) }

  func toggleLike(_ post: LumioPost) {
    if likedIDs.contains(post.id) { likedIDs.remove(post.id) } else { likedIDs.insert(post.id) }
  }

  func toggleSave(_ post: LumioPost) {
    if savedIDs.contains(post.id) { savedIDs.remove(post.id) } else { savedIDs.insert(post.id) }
  }

  func commentsModel(for post: LumioPost) -> CommentsViewModel {
    CommentsViewModel(postID: post.id, load: loadComments, add: addComment)
  }
}
