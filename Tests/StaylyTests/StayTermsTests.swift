import Testing
@testable import Stayly

struct StayTermsTests {
  @Test func theDerivedTermsStayInTheirRanges() {
    for albumID in 1 ... 100 {
      #expect((StayFilter.priceFloor ... StayFilter.priceCeiling).contains(StayTerms.price(albumID)))
      #expect((30 ... 50).contains(StayTerms.ratingTenths(albumID)))
      #expect((2 ... 6).contains(StayTerms.capacity(albumID)))
      #expect(!StayTerms.amenities(albumID).isEmpty)
    }
  }

  @Test func theCoverIsTheFirstPhotoOfTheAlbum() {
    #expect(StayTerms.coverPhotoID(albumID: 1) == 1)
    #expect(StayTerms.coverPhotoID(albumID: 2) == 51)
  }

  @Test func theTermsDoNotChangeFromRunToRun() {
    #expect(StayTerms.price(7) == StayTerms.price(7))
    #expect(StayTerms.amenities(7) == StayTerms.amenities(7))
  }
}
