import SwiftUIWeb

/// Explore's state: the search, the pictures a page at a time.
@MainActor @Observable
final class ExploreViewModel {
  var query = ""
  private(set) var tiles: [LumioTile] = []
  private(set) var state: LoadState = .loading
  private(set) var isLoadingMore = false
  private(set) var reachedEnd = false
  private var page = 0
  /// Counts the searches started; a result that finishes after a newer search started is dropped.
  private var loadSerial = 0
  private let load: any LoadExploreUseCase

  init(load: any LoadExploreUseCase) { self.load = load }

  /// The first page for the current search.
  func search() async {
    loadSerial += 1
    let current = loadSerial
    state = .loading
    page = 0
    reachedEnd = false
    do {
      let found = try await load.execute(page: 1, search: query)
      guard current == loadSerial else { return }
      tiles = found
      page = 1
      reachedEnd = tiles.count < LiveExploreRepository.pageSize
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
      let next = try await load.execute(page: page + 1, search: query)
      guard current == loadSerial else { return }
      reachedEnd = next.count < LiveExploreRepository.pageSize
      tiles.append(contentsOf: next)
      page += 1
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }
}
