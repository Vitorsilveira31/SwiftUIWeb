import SwiftUIWeb

/// An album's pictures, and the one the viewer shows larger, if one is.
@MainActor @Observable
final class AlbumViewModel {
  let album: NeighborlyAlbum
  private(set) var photos: [NeighborlyPhoto] = []
  private(set) var state: LoadState = .loading
  private(set) var selected: NeighborlyPhoto?
  private let photosUseCase: any LoadPhotosUseCase

  init(album: NeighborlyAlbum, load: any LoadPhotosUseCase) {
    self.album = album
    photosUseCase = load
  }

  func load() async {
    state = .loading
    do {
      photos = try await photosUseCase.execute(albumID: album.id)
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  /// Shows a picture larger, or goes back to the grid with nil.
  func select(_ photo: NeighborlyPhoto?) { selected = photo }

  /// The picture before (-1) or after (1) the one shown; the ends of the album stop.
  func step(_ offset: Int) {
    guard let current = selected, let index = photos.firstIndex(where: { $0.id == current.id }) else { return }
    let next = index + offset
    guard photos.indices.contains(next) else { return }
    selected = photos[next]
  }
}
