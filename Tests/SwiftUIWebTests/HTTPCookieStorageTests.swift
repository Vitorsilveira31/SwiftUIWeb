import Testing
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@testable @_spi(Browser) import SwiftUIWebNetworking

/// The browser cookie jar as `HTTPCookieStorage` sees it: a fake `document.cookie` that records what is written.
private final class FakeCookieJar: @unchecked Sendable {
  var cookieString = ""
  var host = "example.test"
  var isSecurePage = true
  var written: [String] = []
}

@Suite(.serialized)
struct HTTPCookieStorageTests {
  private func withJar(_ jar: FakeCookieJar, _ body: () -> Void) {
    CookieJarRuntime.install(
      read: { [jar] in (jar.cookieString, jar.host, jar.isSecurePage) },
      write: { [jar] line in
        jar.written.append(line)
        return true
      }
    )
    defer { CookieJarRuntime.install(read: nil, write: nil) }
    body()
  }

  @Test
  func readsScriptVisibleCookiesFromTheDocument() {
    let jar = FakeCookieJar()
    jar.cookieString = "session=abc; theme=dark;  flag"
    withJar(jar) {
      let cookies = HTTPCookieStorage.shared.cookies ?? []
      #expect(cookies.map(\.name) == ["session", "theme", ""])
      #expect(cookies.map(\.value) == ["abc", "dark", "flag"])
      #expect(cookies.allSatisfy { $0.domain == "example.test" && $0.path == "/" && !$0.isHTTPOnly })
      #expect(cookies.allSatisfy { $0.isSessionOnly })
    }
  }

  @Test
  func emptyJarAndMissingHostReportNoCookies() {
    let jar = FakeCookieJar()
    withJar(jar) {
      #expect(HTTPCookieStorage.shared.cookies == nil)
    }
    // No host installed at all: reads and writes are inert, as in a worker without a document.
    #expect(HTTPCookieStorage.shared.cookies == nil)
    HTTPCookieStorage.shared.setCookie(HTTPCookie(name: "a", value: "b", domain: "example.test", path: "/", expiresDate: nil, isSecure: false, isHTTPOnly: false))
    #expect(jar.written.isEmpty)
  }

  @Test
  func cookiesForURLMatchDomainPathAndScheme() {
    let jar = FakeCookieJar()
    jar.cookieString = "a=1; b=2"
    jar.host = "shop.example.test"
    withJar(jar) {
      let storage = HTTPCookieStorage.shared
      #expect(storage.cookies(for: URL(string: "https://shop.example.test/cart")!)?.count == 2)
      // `document.cookie` does not say which cookies have a Domain attribute, so they are host-only (RFC 6265): a subdomain
      // gets none.
      #expect(storage.cookies(for: URL(string: "https://api.shop.example.test/me")!) == nil)
      // A URL with no path component matches the root path.
      #expect(storage.cookies(for: URL(string: "https://shop.example.test")!)?.count == 2)
      #expect(storage.cookies(for: URL(string: "https://other.test/")!) == nil)
    }
  }

  @Test
  func setCookieWritesAnAttributeLineWithTheBrowserDateFormat() {
    let jar = FakeCookieJar()
    withJar(jar) {
      let cookie = HTTPCookie(name: "pref", value: "compact", domain: "example.test", path: "/app",
                              expiresDate: Date(timeIntervalSince1970: 1_700_000_000), isSecure: true, isHTTPOnly: false)
      HTTPCookieStorage.shared.setCookie(cookie)
      #expect(jar.written == ["pref=compact; Path=/app; Domain=example.test; Expires=Tue, 14 Nov 2023 22:13:20 GMT; Secure"])
    }
  }

  @Test
  func setCookieRefusesHttpOnlyInvalidAndPolicyBlockedCookies() {
    let jar = FakeCookieJar()
    withJar(jar) {
      let storage = HTTPCookieStorage.shared
      storage.setCookie(HTTPCookie(name: "sid", value: "secret", domain: "example.test", path: "/", expiresDate: nil, isSecure: true, isHTTPOnly: true))
      storage.setCookie(HTTPCookie(name: "bad;name", value: "x", domain: "example.test", path: "/", expiresDate: nil, isSecure: false, isHTTPOnly: false))
      storage.setCookie(HTTPCookie(name: "ok", value: "a;b", domain: "example.test", path: "/", expiresDate: nil, isSecure: false, isHTTPOnly: false))
      #expect(jar.written.isEmpty)
      storage.cookieAcceptPolicy = .never
      storage.setCookie(HTTPCookie(name: "ok", value: "1", domain: "example.test", path: "/", expiresDate: nil, isSecure: false, isHTTPOnly: false))
      #expect(jar.written.isEmpty)
      storage.cookieAcceptPolicy = .onlyFromMainDocumentDomain
    }
  }

  @Test
  func pathAndDomainCannotCarryAttributeSeparatorsControlCharactersOrWhitespace() {
    func cookie(domain: String = "example.test", path: String = "/") -> HTTPCookie? {
      HTTPCookie(properties: [.name: "a", .value: "b", .domain: domain, .path: path])
    }
    // An attribute separator, a control character, whitespace or a malformed host is refused.
    #expect(cookie(path: "/app;Domain=evil.test") == nil)
    #expect(cookie(path: "/app\r\nSet-Cookie: x=y") == nil)
    #expect(cookie(path: "/a b") == nil)
    #expect(cookie(path: "/\u{7F}") == nil)
    #expect(cookie(domain: "example.test; Secure") == nil)
    #expect(cookie(domain: "example.test\n") == nil)
    #expect(cookie(domain: "exa mple.test") == nil)
    #expect(cookie(domain: "example,test") == nil)
    #expect(cookie(domain: "..example.test") == nil)
    #expect(cookie(domain: "example..test") == nil)
    // Ordinary values are accepted, including an empty domain for a host-only cookie.
    #expect(cookie(domain: "") != nil)
    #expect(cookie(domain: ".example.test", path: "/shop/cart") != nil)
    #expect(cookie(domain: "api-1.shop.example.test") != nil)
  }

  @Test
  func setCookieRefusesAPathOrDomainThatWouldInjectAnAttribute() {
    let jar = FakeCookieJar()
    withJar(jar) {
      let storage = HTTPCookieStorage.shared
      storage.setCookie(HTTPCookie(name: "a", value: "b", domain: "example.test; Domain=evil.test", path: "/", expiresDate: nil, isSecure: false, isHTTPOnly: false))
      storage.setCookie(HTTPCookie(name: "a", value: "b", domain: "example.test", path: "/;Domain=evil.test", expiresDate: nil, isSecure: false, isHTTPOnly: false))
      #expect(jar.written.isEmpty)
      storage.setCookie(HTTPCookie(name: "a", value: "b", domain: "", path: "/", expiresDate: nil, isSecure: false, isHTTPOnly: false))
      #expect(jar.written == ["a=b; Path=/"])
    }
  }

  @Test
  func deleteCookieExpiresItAtTheEpoch() {
    let jar = FakeCookieJar()
    withJar(jar) {
      let cookie = HTTPCookie(name: "theme", value: "dark", domain: "example.test", path: "/", expiresDate: nil, isSecure: false, isHTTPOnly: false)
      HTTPCookieStorage.shared.deleteCookie(cookie)
      #expect(jar.written == ["theme=; Path=/; Domain=example.test; Expires=Thu, 01 Jan 1970 00:00:00 GMT"])
    }
  }

  @Test
  func aSecureCookieIsSentOnlyToAnHTTPSPage() {
    #expect(_cookieSchemeAllows(cookieIsSecure: false, pageIsSecure: false))
    #expect(_cookieSchemeAllows(cookieIsSecure: false, pageIsSecure: true))
    #expect(_cookieSchemeAllows(cookieIsSecure: true, pageIsSecure: true))
    #expect(!_cookieSchemeAllows(cookieIsSecure: true, pageIsSecure: false))
  }

  @Test
  func stringFlagValuesAreParsedAsTheBrowserWritesThem() {
    func secure(_ value: String) -> Bool? {
      HTTPCookie(properties: [.name: "a", .value: "b", .domain: "example.test", .path: "/", .secure: value])?.isSecure
    }
    #expect(secure("TRUE") == true)
    #expect(secure("true") == true)
    #expect(secure("1") == true)
    #expect(secure("YES") == true)
    #expect(secure("no") == false)
  }

  @Test
  func propertiesRequireNameValueDomainAndPath() {
    #expect(HTTPCookie(properties: [.name: "a", .value: "b", .domain: "example.test", .path: "/"]) != nil)
    #expect(HTTPCookie(properties: [.name: "a", .value: "b", .domain: "example.test"]) == nil)
    #expect(HTTPCookie(properties: [.name: "a;b", .value: "b", .domain: "example.test", .path: "/"]) == nil)
    let secure = HTTPCookie(properties: [.name: "a", .value: "b", .domain: ".example.test", .path: "/", .secure: "TRUE"])
    #expect(secure?.isSecure == true)
    // Apple's value types: Bool flags, an Int version and a Date expiry.
    let typed = HTTPCookie(properties: [.name: "a", .value: "b", .domain: "example.test", .path: "/",
                                        .secure: true, HTTPCookiePropertyKey("HttpOnly"): false, .version: 1,
                                        .expires: Date(timeIntervalSince1970: 1_700_000_000)])
    #expect(typed?.isSecure == true && typed?.isHTTPOnly == false && typed?.version == 1)
    #expect(typed?.expiresDate == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(HTTPCookie(properties: [.name: 1, .value: "b", .domain: "example.test", .path: "/"]) == nil)
  }

  @Test
  func sessionConfigurationCarriesTheCookieStorageAndPolicy() {
    let configuration = URLSessionConfiguration()
    #expect(configuration.httpCookieStorage === HTTPCookieStorage.shared)
    #expect(configuration.httpCookieAcceptPolicy == .onlyFromMainDocumentDomain)
  }

  @Test
  func setCookiesWritesEachCookieInOrderWhateverURLItIsGiven() {
    let jar = FakeCookieJar()
    withJar(jar) {
      let cookies = [
        HTTPCookie(name: "a", value: "1", domain: "example.test", path: "/", expiresDate: nil, isSecure: false, isHTTPOnly: false),
        HTTPCookie(name: "b", value: "2", domain: "example.test", path: "/", expiresDate: nil, isSecure: false, isHTTPOnly: false),
      ]
      HTTPCookieStorage.shared.setCookies(cookies, for: URL(string: "https://example.test/")!, mainDocumentURL: nil)
      let first = jar.written
      #expect(first.count == 2)
      #expect(first.first?.hasPrefix("a=1") == true)
      #expect(first.last?.hasPrefix("b=2") == true)

      // The URL does not change where the browser stores a cookie: the same lines are written for another URL.
      HTTPCookieStorage.shared.setCookies(cookies, for: URL(string: "https://other.test/")!, mainDocumentURL: nil)
      #expect(jar.written == first + first)
    }
  }

  @MainActor
  @Test
  func observeChangesRunsTheHandlerAtEachChangeUntilItIsStopped() {
    final class Counter { var count = 0 }
    let counter = Counter()
    let stop = HTTPCookieStorage.shared.observeChanges { counter.count += 1 }

    CookieJarRuntime.notifyChanged()
    #expect(counter.count == 1)
    CookieJarRuntime.notifyChanged()
    #expect(counter.count == 2)

    stop()
    CookieJarRuntime.notifyChanged()
    #expect(counter.count == 2)
  }

  @Test
  func aDotDomainCookieReachesNoHostThroughTheJar() {
    let jar = FakeCookieJar()
    jar.cookieString = "token=1"
    jar.host = "."
    withJar(jar) {
      #expect(HTTPCookieStorage.shared.cookies?.first?.domain == ".")
      #expect(HTTPCookieStorage.shared.cookies(for: URL(string: "https://example.test/")!) == nil)
    }
  }
  @Test
  func aDotDomainCookieReachesTheDomainsSubdomains() {
    let jar = FakeCookieJar()
    jar.cookieString = "token=1"
    jar.host = ".example.test"
    withJar(jar) {
      // A subdomain is not the domain itself, so the suffix decides.
      #expect(HTTPCookieStorage.shared.cookies(for: URL(string: "https://www.example.test/a")!)?.first?.name == "token")
      #expect(HTTPCookieStorage.shared.cookies(for: URL(string: "https://other.test/a")!) == nil)
    }
  }

  @Test
  func aURLWithNoPathAfterTheHostStillMatchesItsHost() {
    let jar = FakeCookieJar()
    jar.cookieString = "token=1"
    jar.host = "example.test"
    withJar(jar) {
      // "https://example.test" has no "/" after the authority: the host runs to the end of the address.
      #expect(HTTPCookieStorage.shared.cookies(for: URL(string: "https://example.test")!)?.first?.name == "token")
    }
  }
  @Test
  func aPlainHTTPPageGetsTheHostsNonSecureCookie() {
    let jar = FakeCookieJar()
    jar.cookieString = "token=1"
    jar.host = "example.test"
    withJar(jar) {
      // http is a web scheme too (a backslash ends its authority), but not a secure one.
      #expect(HTTPCookieStorage.shared.cookies(for: URL(string: "http://example.test/a")!)?.first?.name == "token")
    }
  }
}
