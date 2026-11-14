import Testing
@testable import SwiftUIWebFeatures

/// The ids of a `scrollTargetVisibility` event are percent-encoded by the host, so an id that holds the list's "," or a
/// "%" reads back whole, and a malformed escape is dropped instead of read as another id.
@Suite
struct ScrollVisibilityIDTests {
  @Test
  func idsWithTheSeparatorReadBackWhole() {
    #expect(_scrollPercentDecoded("a%2Cb") == "a,b")
    #expect(_scrollPercentDecoded("100%25") == "100%")
    #expect(_scrollPercentDecoded("caf%C3%A9") == "café")
    #expect(_scrollPercentDecoded("plain") == "plain")
    #expect(_scrollPercentDecoded("%ZZ") == nil)
    #expect(_scrollPercentDecoded("%C3") == nil)
    #expect(_scrollPercentDecoded("%2") == nil)
  }
}
