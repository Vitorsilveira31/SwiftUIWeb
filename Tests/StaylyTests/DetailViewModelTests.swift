import Testing
@testable import Stayly

@MainActor
struct DetailViewModelTests {
  private func make(_ stays: StubStays, session: StaySession, stay target: Stay = stay(5, price: 120)) -> DetailViewModel {
    DetailViewModel(stay: target, query: search(nights: 3, guests: 4), loadDetail: stays, reserve: stays, session: session)
  }

  @Test func theDetailLoadsWithItsFirstPhoto() async {
    let stays = StubStays()
    stays.detail = detail(stay(5), photos: 3)
    let model = make(stays, session: StaySession())
    await model.load()
    #expect(model.state == .loaded)
    #expect(model.detail?.photos.count == 3)
    #expect(model.photoIndex == 0)
  }

  @Test func aPhotoOutsideTheGalleryIsIgnored() async {
    let stays = StubStays()
    stays.detail = detail(stay(5), photos: 3)
    let model = make(stays, session: StaySession())
    await model.load()
    model.select(photo: 2)
    #expect(model.photoIndex == 2)
    model.select(photo: 3)
    #expect(model.photoIndex == 2)
    model.select(photo: -1)
    #expect(model.photoIndex == 2)
  }

  @Test func aFailedDetailSaysSo() async {
    let stays = StubStays()
    stays.fails = true
    let model = make(stays, session: StaySession())
    await model.load()
    #expect(model.state == .failed(FailureText.unreachable))
  }

  @Test func theTotalIsTheNightsTimesThePrice() {
    let model = make(StubStays(), session: StaySession())
    #expect(model.total == 360)
  }

  @Test func reservingRecordsATripOnceAndKeepsIt() async {
    let stays = StubStays()
    let session = StaySession()
    let model = make(stays, session: session)
    await model.reserve()
    await model.reserve()
    #expect(stays.reservations == 1)
    #expect(model.reservation?.guests == 4)
    #expect(model.reservation?.total == 360)
    #expect(session.reservations.map(\.stay.id) == [5])
  }

  @Test func aFailedReservationRecordsNothing() async {
    let stays = StubStays()
    let session = StaySession()
    let model = make(stays, session: session)
    stays.fails = true
    await model.reserve()
    #expect(model.reserveFailed)
    #expect(model.reservation == nil)
    #expect(session.reservations.isEmpty)
  }
}
