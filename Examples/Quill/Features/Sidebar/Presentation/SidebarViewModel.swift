import SwiftUIWeb

/// The right column: the people to follow and the trends, and which of the people the reader follows.
@MainActor @Observable
final class SidebarViewModel {
  private(set) var people: [QuillUser] = []
  private(set) var trends: [QuillTrend] = []
  private(set) var state: LoadState = .loading
  private(set) var followedIDs: Set<Int> = []
  private let loadWhoToFollow: any LoadWhoToFollowUseCase
  private let loadTrends: any LoadTrendsUseCase

  init(loadWhoToFollow: any LoadWhoToFollowUseCase, loadTrends: any LoadTrendsUseCase) {
    self.loadWhoToFollow = loadWhoToFollow
    self.loadTrends = loadTrends
  }

  /// Both lists; also what Try again runs.
  func load() async {
    state = .loading
    do {
      people = try await loadWhoToFollow.execute()
      trends = try await loadTrends.execute()
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  func isFollowing(_ user: QuillUser) -> Bool { followedIDs.contains(user.id) }

  func toggleFollow(_ user: QuillUser) {
    if followedIDs.contains(user.id) { followedIDs.remove(user.id) } else { followedIDs.insert(user.id) }
  }
}
