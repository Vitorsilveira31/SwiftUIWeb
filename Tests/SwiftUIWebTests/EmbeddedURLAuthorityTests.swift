import Testing
@testable import Foundation

/// The Embedded URL accessors must read the authority the way the browser fetch parser (WHATWG) does, on the inputs
/// where a plain string search disagrees. Expected values were read from `new URL(...)` in JavaScript.
@Suite
struct EmbeddedURLAuthorityTests {
  @Test
  func backslashEndsTheAuthorityOfASpecialScheme() {
    let attack = _EmbeddedURLParts.parse("https:\\\\evil.example\\a")
    _expectEqual(attack?.scheme, "https")
    _expectEqual(attack?.host, "evil.example")
    _expectEqual(attack?.path, "/a")

    let userinfo = _EmbeddedURLParts.parse("https://evil.example\\@api.trusted.example/x")
    _expectEqual(userinfo?.host, "evil.example")
    _expectEqual(userinfo?.path, "/@api.trusted.example/x")
  }

  @Test
  func schemeWithoutDoubleSlashStillHasAnAuthority() {
    _expectEqual(_EmbeddedURLParts.parse("https:/evil.example")?.scheme, "https")
    _expectEqual(_EmbeddedURLParts.parse("https:/evil.example")?.host, "evil.example")
    _expectEqual(_EmbeddedURLParts.parse("http:evil.example")?.host, "evil.example")
    _expectEqual(_EmbeddedURLParts.parse("http:///evil.example/x")?.host, "evil.example")
    _expectEqual(_EmbeddedURLParts.parse("http:///evil.example/x")?.path, "/x")
  }

  @Test
  func ipv6HostKeepsItsBracketsAndPort() {
    let loopback = _EmbeddedURLParts.parse("http://[::1]:8080/x")
    _expectEqual(loopback?.host, "[::1]")
    _expectEqual(loopback?.port, 8080)
    _expectEqual(loopback?.path, "/x")

    let documentation = _EmbeddedURLParts.parse("http://[2001:db8::1]/")
    _expectEqual(documentation?.host, "[2001:db8::1]")
    _expectEqual(documentation?.port, nil)
  }

  @Test
  func userinfoIsIgnoredAndPortIsRead() {
    let parts = _EmbeddedURLParts.parse("http://user:pw@host:99/")
    _expectEqual(parts?.host, "host")
    _expectEqual(parts?.port, 99)
    _expectEqual(parts?.path, "/")
  }

  @Test
  func schemeAndHostAreCaseInsensitive() {
    let parts = _EmbeddedURLParts.parse("HTTPS://EXAMPLE.COM:443/")
    _expectEqual(parts?.scheme, "https")
    _expectEqual(parts?.host, "example.com")
    _expectEqual(parts?.port, 443)
  }

  @Test
  func schemeRelativeStringHasAHostButNoScheme() {
    let parts = _EmbeddedURLParts.parse("//host/path")
    _expectEqual(parts?.scheme, nil)
    _expectEqual(parts?.host, "host")
    _expectEqual(parts?.path, "/path")
  }

  @Test
  func relativeStringsHaveNoSchemeHostOrPort() {
    let relative = _EmbeddedURLParts.parse("a/b?x#y")
    _expectEqual(relative?.scheme, nil)
    _expectEqual(relative?.host, nil)
    _expectEqual(relative?.port, nil)
    _expectEqual(relative?.path, "a/b")
    _expectEqual(_EmbeddedURLParts.parse("/path")?.path, "/path")
  }

  @Test
  func wellFormedHTTPSURLIsUnchanged() {
    let parts = _EmbeddedURLParts.parse("https://example.com:8443/a?b#c")
    _expectEqual(parts?.scheme, "https")
    _expectEqual(parts?.host, "example.com")
    _expectEqual(parts?.port, 8443)
    _expectEqual(parts?.path, "/a")
  }

  @Test
  func unparseableAuthorityReturnsNilInsteadOfAWrongComponent() {
    _expectNil(_EmbeddedURLParts.parse("http://"))
    _expectNil(_EmbeddedURLParts.parse("http://[::1/x"))
    _expectNil(_EmbeddedURLParts.parse("http://host:bad/"))
    _expectNil(_EmbeddedURLParts.parse("http://host:99999/"))
    _expectNil(_EmbeddedURLParts.parse("http://a b/"))
  }

  @Test
  func leadingAndTrailingControlsAndSpacesAreDropped() {
    let parts = _EmbeddedURLParts.parse("  \t\u{1}https://example.com/x \n ")
    _expectEqual(parts?.scheme, "https")
    _expectEqual(parts?.host, "example.com")
    _expectEqual(parts?.path, "/x")
    _expectEqual(_EmbeddedURLParts.parse("ht\ttp://exa\nmple.com/")?.host, "example.com")
  }

  @Test
  func nonSpecialSchemeKeepsItsHostCaseAndNeedsDoubleSlash() {
    let parts = _EmbeddedURLParts.parse("foo://Host:1/p")
    _expectEqual(parts?.scheme, "foo")
    _expectEqual(parts?.host, "Host")
    _expectEqual(parts?.port, 1)
    _expectEqual(parts?.path, "/p")

    let noAuthority = _EmbeddedURLParts.parse("foo:/p")
    _expectEqual(noAuthority?.host, nil)
    // Without an authority the path stays the whole string, as before this parser existed.
    _expectEqual(noAuthority?.path, "foo:/p")
    _expectEqual(_EmbeddedURLParts.parse("foo:///p")?.host, nil)
  }

  @Test
  func fileSchemeMayHaveAnEmptyHostButNotAPortWithoutOne() {
    let parts = _EmbeddedURLParts.parse("file:///x")
    _expectEqual(parts?.scheme, "file")
    _expectEqual(parts?.host, nil)
    _expectEqual(parts?.path, "/x")
    _expectNil(_EmbeddedURLParts.parse("file://:80/x"))
    _expectNil(_EmbeddedURLParts.parse("foo://:80/x"))
  }

  @Test
  func malformedIPv6LiteralsAreRefused() {
    _expectNil(_EmbeddedURLParts.parse("http://[]/"))
    _expectNil(_EmbeddedURLParts.parse("http://[::g]/"))
    _expectNil(_EmbeddedURLParts.parse("http://[::1]x/"))
    _expectNil(_EmbeddedURLParts.parse("http://[::1]:99999/"))
    _expectEqual(_EmbeddedURLParts.parse("http://[::1]:/")?.port, nil)
  }
}
