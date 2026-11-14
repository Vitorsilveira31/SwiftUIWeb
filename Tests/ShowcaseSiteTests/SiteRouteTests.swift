import Testing
@testable import ShowcaseSite

struct SiteRouteTests {
  @Test func anAddressNamesLanguagePageAndEntry() {
    #expect(SiteRoute.parse(path: "/pt/components/slider") == SiteRoute(language: .pt, page: .components, entry: "slider"))
    #expect(SiteRoute.parse(path: "/en/purpose") == SiteRoute(language: .en, page: .purpose, entry: nil))
  }

  @Test func theLanguageMayBeLeftOut() {
    #expect(SiteRoute.parse(path: "/components/text") == SiteRoute(language: nil, page: .components, entry: "text"))
    #expect(SiteRoute.parse(path: "benefits") == SiteRoute(language: nil, page: .benefits, entry: nil))
  }

  @Test func onlyTheComponentsPageHasEntries() {
    #expect(SiteRoute.parse(path: "/en/purpose/slider")?.entry == nil)
  }

  @Test func anAddressOfNoPageIsNotARoute() {
    #expect(SiteRoute.parse(path: "/") == nil)
    #expect(SiteRoute.parse(path: "/en/nothing") == nil)
    #expect(SiteRoute.parse(path: "/index.html") == nil)
  }

  @Test func anAddressOfOnlyALanguageOpensItsFirstPage() {
    #expect(SiteRoute.parse(path: "/pt") == SiteRoute(language: .pt, page: .purpose, entry: nil))
    #expect(SiteRoute.parse(path: "/en/") == SiteRoute(language: .en, page: .purpose, entry: nil))
  }

  @Test func theGettingStartedPageHasItsOwnAddress() {
    #expect(SiteRoute.parse(path: "/en/start") == SiteRoute(language: .en, page: .start, entry: nil))
  }

  @Test func theSegmentsAreWhatParseReads() {
    let route = SiteRoute(language: .pt, page: .components, entry: "stepper")
    #expect(route.segments == ["pt", "components", "stepper"])
    #expect(SiteRoute.parse(path: "/" + route.segments.joined(separator: "/")) == route)
  }

  @Test func aPageWithoutEntriesDropsTheEntryFromItsSegments() {
    #expect(SiteRoute(language: .en, page: .purpose, entry: "slider").segments == ["en", "purpose"])
  }
}
