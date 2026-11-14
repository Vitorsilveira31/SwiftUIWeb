import SwiftUIWeb

/// The Photos tab's state: whose albums are shown, those albums, and the album open in the viewer, if one is.
@MainActor @Observable
final class PhotosViewModel {
  private(set) var personID: Int
  private(set) var albums: [NeighborlyAlbum] = []
  private(set) var state: LoadState = .loading
  private(set) var album: AlbumViewModel?
  /// Counts the loads started; a result that finishes after a newer load started is dropped.
  private var loadSerial = 0
  private let albumsUseCase: any LoadAlbumsUseCase
  private let photosUseCase: any LoadPhotosUseCase

  init(personID: Int, loadAlbums: any LoadAlbumsUseCase, loadPhotos: any LoadPhotosUseCase) {
    self.personID = personID
    albumsUseCase = loadAlbums
    photosUseCase = loadPhotos
  }

  /// The albums of the person shown; also what Try again runs.
  func load() async {
    loadSerial += 1
    let current = loadSerial
    state = .loading
    do {
      let found = try await albumsUseCase.execute(userID: personID)
      guard current == loadSerial else { return }
      albums = found
      state = .loaded
    } catch {
      guard current == loadSerial else { return }
      state = .failed(FailureText.unreachable)
    }
  }

  /// Shows another person's albums, closing the album that was open.
  func selectPerson(_ id: Int) async {
    personID = id
    album = nil
    albums = []
    await load()
  }

  func openAlbum(_ album: NeighborlyAlbum) {
    let viewer = AlbumViewModel(album: album, load: photosUseCase)
    self.album = viewer
    Task { await viewer.load() }
  }

  func closeAlbum() { album = nil }
}
