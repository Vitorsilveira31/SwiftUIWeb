import SwiftUIWeb

/// The timeline: the feed the reader chose, a page at a time, what they liked and reposted, and the post whose thread is open.
@MainActor @Observable
final class TimelineViewModel {
  private(set) var feed: QuillFeed = .forYou
  private(set) var posts: [QuillPost] = []
  private(set) var state: LoadState = .loading
  private(set) var isLoadingMore = false
  private(set) var reachedEnd = false
  private(set) var likedIDs: Set<Int> = []
  private(set) var repostedIDs: Set<Int> = []
  /// The post whose thread is open, if any, and the thread's own state.
  private(set) var opened: QuillPost?
  private(set) var thread: PostDetailViewModel?
  /// Whether the composer is open (on a phone it is a sheet; on a wide window it is also at the top of the feed).
  var composing = false
  private var page = 0
  private let loadTimeline: any LoadTimelineUseCase
  private let loadReplies: any LoadRepliesUseCase
  private let addReply: any AddReplyUseCase

  init(loadTimeline: any LoadTimelineUseCase, loadReplies: any LoadRepliesUseCase, addReply: any AddReplyUseCase) {
    self.loadTimeline = loadTimeline
    self.loadReplies = loadReplies
    self.addReply = addReply
  }

  /// The first page of the chosen feed; also what Try again runs.
  func load() async {
    state = .loading
    page = 0
    do {
      posts = try await loadTimeline.execute(feed: feed, page: 1)
      page = 1
      reachedEnd = feed == .following
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  func select(_ next: QuillFeed) async {
    guard next != feed else { return }
    feed = next
    posts = []
    await load()
  }

  func loadMore() async {
    guard state == .loaded, !isLoadingMore, !reachedEnd else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let next = try await loadTimeline.execute(feed: feed, page: page + 1)
      reachedEnd = next.isEmpty
      posts.append(contentsOf: next)
      page += 1
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  /// Puts a post the reader just wrote at the top of the feed.
  func prepend(_ post: QuillPost) {
    posts.insert(post, at: 0)
  }

  func isLiked(_ post: QuillPost) -> Bool { likedIDs.contains(post.id) }

  func isReposted(_ post: QuillPost) -> Bool { repostedIDs.contains(post.id) }

  /// The counts shown: the post's, plus the reader's own action.
  func likes(of post: QuillPost) -> Int { post.likes + (isLiked(post) ? 1 : 0) }

  func reposts(of post: QuillPost) -> Int { post.reposts + (isReposted(post) ? 1 : 0) }

  func replies(of post: QuillPost) -> Int {
    (posts.first { $0.id == post.id } ?? post).replies
  }

  func toggleLike(_ post: QuillPost) {
    toggle(post.id, in: &likedIDs)
  }

  func toggleRepost(_ post: QuillPost) {
    toggle(post.id, in: &repostedIDs)
  }

  /// Opens the thread of a post.
  func open(_ post: QuillPost) {
    thread = threadModel(for: post)
    opened = post
  }

  /// Ends the open thread. The post shows the replies sent in it, so it has one count more for each.
  func finishThread() {
    let sent = thread?.sentCount ?? 0
    let postID = opened?.id
    opened = nil
    thread = nil
    guard sent > 0, let postID, let index = posts.firstIndex(where: { $0.id == postID }) else { return }
    posts[index] = posts[index].addingReplies(sent)
  }

  func threadModel(for post: QuillPost) -> PostDetailViewModel {
    PostDetailViewModel(post: post, loadReplies: loadReplies, addReply: addReply)
  }

  private func toggle(_ id: Int, in set: inout Set<Int>) {
    if set.contains(id) { set.remove(id) } else { set.insert(id) }
  }
}
