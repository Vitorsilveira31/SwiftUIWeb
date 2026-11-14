import Testing
@testable import Neighborly

@MainActor
struct PhotosViewModelTests {
  private func album(_ id: Int) -> NeighborlyAlbum { NeighborlyAlbum(id: id, title: "album \(id)", coverURL: "/c\(id).svg") }

  @Test func theAlbumsOfThePersonAreLoaded() async {
    let stub = StubPhotos()
    stub.albums[1] = [album(1), album(2)]
    let model = PhotosViewModel(personID: 1, loadAlbums: stub, loadPhotos: stub)
    await model.load()
    #expect(model.state == .loaded)
    #expect(model.albums.map(\.id) == [1, 2])
  }

  @Test func pickingAnotherPersonLoadsTheirAlbums() async {
    let stub = StubPhotos()
    stub.albums[2] = [album(21)]
    let model = PhotosViewModel(personID: 1, loadAlbums: stub, loadPhotos: stub)
    await model.load()
    await model.selectPerson(2)
    #expect(model.personID == 2)
    #expect(model.albums.map(\.id) == [21])
    #expect(stub.requestedPeople == [1, 2])
  }

  @Test func openingAnAlbumShowsItsPicturesAndOnePictureCanBeChosen() async {
    let stub = StubPhotos()
    stub.albums[1] = [album(1)]
    stub.photos[1] = photos(3)
    let model = PhotosViewModel(personID: 1, loadAlbums: stub, loadPhotos: stub)
    await model.load()
    model.openAlbum(model.albums[0])
    let viewer = model.album
    await viewer?.load()
    #expect(viewer?.photos.count == 3)
    viewer?.select(viewer?.photos[1])
    #expect(viewer?.selected?.title == "p2")
  }

  @Test func stepsMoveThroughThePicturesAndStopAtTheEnds() async {
    let stub = StubPhotos()
    stub.photos[1] = photos(2)
    let model = AlbumViewModel(album: NeighborlyAlbum(id: 1, title: "t", coverURL: "/c"), load: stub)
    await model.load()
    model.select(model.photos[0])
    model.step(-1)
    #expect(model.selected?.title == "p1")
    model.step(1)
    #expect(model.selected?.title == "p2")
    model.step(1)
    #expect(model.selected?.title == "p2")
    model.select(nil)
    #expect(model.selected == nil)
  }

  @Test func closingTheAlbumGoesBackToTheAlbums() async {
    let stub = StubPhotos()
    stub.albums[1] = [album(1)]
    let model = PhotosViewModel(personID: 1, loadAlbums: stub, loadPhotos: stub)
    await model.load()
    model.openAlbum(model.albums[0])
    model.closeAlbum()
    #expect(model.album == nil)
  }
}
