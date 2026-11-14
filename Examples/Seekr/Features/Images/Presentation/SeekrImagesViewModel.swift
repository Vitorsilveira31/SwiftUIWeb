import SwiftUIWeb

/// The Images tab: the pictures of the submitted search, a page at a time, and the one the preview shows.
@MainActor @Observable
final class SeekrImagesViewModel {
  private(set) var query = ""
  private(set) var pictures: [SeekrPicture] = []
  private(set) var state: LoadState = .loading
  private(set) var isLoadingMore = false
  private(set) var reachedEnd = false
  private(set) var selected: SeekrPicture?
  private var page = 0
  private let searchPictures: any SearchPicturesUseCase

  init(searchPictures: any SearchPicturesUseCase) { self.searchPictures = searchPictures }

  /// The first page for a new search; the preview closes.
  func run(_ text: String) async {
    query = text
    selected = nil
    state = .loading
    page = 0
    reachedEnd = false
    do {
      pictures = try await searchPictures.execute(query: query, page: 1)
      page = 1
      reachedEnd = pictures.count < LivePictureRepository.pageSize
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
      let next = try await searchPictures.execute(query: query, page: page + 1)
      reachedEnd = next.count < LivePictureRepository.pageSize
      pictures.append(contentsOf: next)
      page += 1
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  func select(_ picture: SeekrPicture?) { selected = picture }
}
