import Testing
@testable import Lumio

@MainActor
struct ExploreViewModelTests {
  @Test func searchingLoadsTheFirstPageForTheQuery() async {
    let stub = StubExplore()
    stub.tiles[1] = tiles(LiveExploreRepository.pageSize)
    let model = ExploreViewModel(load: stub)
    model.query = "harbor"
    await model.search()
    #expect(stub.searches == ["1:harbor"])
    #expect(model.tiles.count == LiveExploreRepository.pageSize)
    #expect(!model.reachedEnd)
  }

  @Test func aShortPageIsTheLastOne() async {
    let stub = StubExplore()
    stub.tiles[1] = tiles(5)
    let model = ExploreViewModel(load: stub)
    await model.search()
    #expect(model.reachedEnd)
    await model.loadMore()
    #expect(stub.searches == ["1:"])
  }

  @Test func moreAppendsAndANewSearchStartsOver() async {
    let stub = StubExplore()
    stub.tiles[1] = tiles(LiveExploreRepository.pageSize)
    stub.tiles[2] = tiles(3, from: 100)
    let model = ExploreViewModel(load: stub)
    await model.search()
    await model.loadMore()
    #expect(model.tiles.count == LiveExploreRepository.pageSize + 3)
    #expect(model.reachedEnd)
    model.query = "new"
    await model.search()
    #expect(stub.searches.last == "1:new")
    #expect(!model.reachedEnd || model.tiles.count < LiveExploreRepository.pageSize)
  }
}
