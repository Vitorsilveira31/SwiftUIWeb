import Testing
@testable import SwiftUIWebNetworking

@Suite
struct HTTPTokenTests {
  @Test
  func tokenCharactersFollowRFC9110() {
    _expectTrue(isHTTPToken("Accept"))
    _expectTrue(isHTTPToken("X-Request-ID"))
    _expectTrue(isHTTPToken("a!b"))
    _expectTrue(isHTTPToken("*"))
    _expectTrue(isHTTPToken("!#$%&'*+-.^_`|~0aZ"))
    _expectFalse(isHTTPToken(""))
    _expectFalse(isHTTPToken("X\r\nInjected"))
    _expectFalse(isHTTPToken("X Test"))
    _expectFalse(isHTTPToken("Content:Type"))
    _expectFalse(isHTTPToken("名"))
  }
}
