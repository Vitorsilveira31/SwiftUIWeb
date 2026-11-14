import Testing
import Foundation
@testable import SwiftUIWeb
@testable import SwiftUIWebNetworking

/// URLs built or read from data keep their parts apart, and a timeout of any size converts without trapping.
@Suite
struct NetworkURLLimitTests {
  @Test
  func aQuestionMarkInTheFragmentIsNotAQuery() {
    #expect(URL(string: "https://a.example/#x?next=evil")?.query == nil)
    #expect(URL(string: "https://a.example/p?q=1#frag?x")?.query == "q=1")
  }

  @Test
  func componentsCannotMoveTheAuthority() {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "example.com"
    components.path = "@evil.com"
    #expect(components.url == nil)
    components.path = "/a?x=1#f"
    #expect(components.url?.absoluteString == "https://example.com/a%3Fx=1%23f")
    #expect(components.url?.query == nil)
    components.path = "/ok"
    components.host = "evil.com/x"
    #expect(components.url == nil)
    components.host = "example.com"
    #expect(components.url?.absoluteString == "https://example.com/ok")
  }

  @Test
  func timeoutsSaturate() {
    #expect(_timeoutNanoseconds(1e11) == UInt64.max)
    #expect(_timeoutNanoseconds(.infinity) == 0)
    #expect(_timeoutNanoseconds(1.5) == 1_500_000_000)
  }
}
