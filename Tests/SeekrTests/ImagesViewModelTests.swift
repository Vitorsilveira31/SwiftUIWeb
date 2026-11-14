import Testing
@testable import Seekr

@MainActor
struct ImagesViewModelTests {
  @Test func aSearchLoadsTheFirstPageOfPictures() async {
    let pictures = StubPictures()
    pictures.pages[1] = (1...LivePictureRepository.pageSize).map { picture($0) }
    let model = SeekrImagesViewModel(searchPictures: pictures)
    await model.run("harbor")
    #expect(pictures.requested == ["harbor:1"])
    #expect(model.pictures.count == LivePictureRepository.pageSize)
    #expect(!model.reachedEnd)
    #expect(model.state == .loaded)
  }

  @Test func showMoreAddsTheNextPageAndAShortPageIsTheLast() async {
    let pictures = StubPictures()
    pictures.pages[1] = (1...LivePictureRepository.pageSize).map { picture($0) }
    pictures.pages[2] = [picture(100)]
    let model = SeekrImagesViewModel(searchPictures: pictures)
    await model.run("harbor")
    await model.loadMore()
    #expect(model.pictures.count == LivePictureRepository.pageSize + 1)
    #expect(model.reachedEnd)
    await model.loadMore()
    #expect(pictures.requested == ["harbor:1", "harbor:2"])
  }

  @Test func aNewSearchClosesThePreview() async {
    let pictures = StubPictures()
    pictures.pages[1] = [picture(1)]
    let model = SeekrImagesViewModel(searchPictures: pictures)
    await model.run("harbor")
    model.select(picture(1))
    #expect(model.selected?.id == 1)
    await model.run("bread")
    #expect(model.selected == nil)
    #expect(model.query == "bread")
  }

  @Test func aFailedSearchSaysItCouldNotReachTheService() async {
    let pictures = StubPictures()
    pictures.fails = true
    let model = SeekrImagesViewModel(searchPictures: pictures)
    await model.run("harbor")
    #expect(model.state == .failed(FailureText.unreachable))
  }
}
