import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@testable import SwiftUIWebInternationalization
@testable @_spi(Browser) import SwiftUIWebNetworking
@testable import SwiftUIWebBrowserIO
@testable import SwiftUIWebLocking
@testable import SwiftUIWebUniformTypeIdentifiers
import SwiftUIWebHTML
import SwiftUIWebMapKit

/// Values that come from outside the app (a server's headers, a date, a map style URL, a browser's week, a cookie jar)
/// must not trap or leak into the output. Each test feeds one such value and checks the result the framework gives.
@Suite(.serialized)
@MainActor
struct DataValueHardeningTests {
  /// The browser cookie jar as `HTTPCookieStorage` sees it: a fake `document.cookie` on `host`.
  private final class FakeJar: @unchecked Sendable {
    var cookieString = "a=1"
    var host = "shop.example.test"
  }

  private func withJar(_ jar: FakeJar, _ body: () -> Void) {
    CookieJarRuntime.install(
      read: { [jar] in (jar.cookieString, jar.host, true) },
      write: { _ in true }
    )
    defer { CookieJarRuntime.install(read: nil, write: nil) }
    body()
  }

  // Item 3: a Content-Length that is negative or not a number is unknown (-1), never a count.
  @Test
  func contentLengthOutsideTheCountsIsUnknown() {
    #expect(_expectedContentLength(headers: ["Content-Length": "-5"]) == -1)
    #expect(_expectedContentLength(headers: ["Content-Length": "abc"]) == -1)
    #expect(_expectedContentLength(headers: ["Content-Length": "99999999999999999999999999"]) == -1)
    #expect(_expectedContentLength(headers: ["Content-Length": "12"]) == 12)
  }

  // Item 7: the sign and the fraction of a negative epoch are split, so -2.3 is not read as -2.7.
  @Test
  func epochTextKeepsTheSignOfNegativeFractions() {
    #expect(_swiftUIWebEpochText(-2.3) == "-2.3")
    #expect(_swiftUIWebEpochText(-0.5) == "-0.5")
    #expect(_swiftUIWebEpochText(0) == "0")
    #expect(_swiftUIWebEpochText(2.3) == "2.3")
  }

  // Item 10: a sleep of NaN or of a few milliseconds returns; an infinite sleep is capped instead of trapping.
  @Test
  func hostSleepIgnoresNaNAndShortSleepsReturn() {
    _swiftUIWebHostSleep(seconds: .nan)
    _swiftUIWebHostSleep(seconds: 0.001)
  }

  // Item 12: a week value above Int32.max is not a day; it fails the guard instead of trapping on wasm32.
  @Test
  func browserWeekValuesOutsideTheirRangesAreIgnored() {
    var outOfRange = IOReader(bytes: {
      var writer = IOWriter()
      writer.u32(1); writer.u32(0xFFFF_FFFF); writer.u32(0xFFFF_FFFF)
      return writer.bytes
    }())
    #expect(BrowserIntl._decodeWeekInfo(&outOfRange) == nil)

    var minimalOutOfRange = IOReader(bytes: {
      var writer = IOWriter()
      writer.u32(1); writer.u32(2); writer.u32(0xFFFF_FFFF)
      return writer.bytes
    }())
    let week = BrowserIntl._decodeWeekInfo(&minimalOutOfRange)
    #expect(week?.firstWeekday == 3)
    #expect(week?.minimumDays == 1)
  }

  // Item 15: `mp4` is the MPEG-4 movie type, and a wildcard MIME type names no single type.
  @Test
  func mp4IsAnMPEG4MovieAndWildcardMIMETypesAreNotTypes() {
    #expect(UTType(filenameExtension: "mp4") == .mpeg4Movie)
    #expect(UTType(mimeType: "video/*") == nil)
    #expect(UTType(mimeType: "image/*") == nil)
    #expect(UTType(mimeType: "video/mp4") == .mpeg4Movie)
  }

  // Item 16: a host-only cookie (the page's own cookies, as script sees them) is not sent to a subdomain, and the
  // scheme and a backslash in the URL are read the way a browser reads them.
  @Test
  func hostOnlyCookiesStayOnTheirHost() throws {
    let jar = FakeJar()
    let ownPage = try #require(URL(string: "https://shop.example.test/cart"))
    let subdomain = try #require(URL(string: "https://api.shop.example.test/me"))
    let upperCase = try #require(URL(string: "HTTPS://SHOP.example.test/"))
    let backslash = try #require(URL(string: "https://shop.example.test\\evil.test/"))
    withJar(jar) {
      let storage = HTTPCookieStorage.shared
      #expect(storage.cookies(for: ownPage)?.count == 1)
      #expect(storage.cookies(for: subdomain) == nil)
      // The scheme is case-insensitive, and the host is compared lowercased.
      #expect(storage.cookies(for: upperCase) != nil)
      // For http(s) a backslash ends the authority, so the host here is shop.example.test.
      #expect(storage.cookies(for: backslash) != nil)
    }
  }

  // Items 6b and 6c: a map's style URL shows no userinfo or credential query item, and
  // attribution text reaches the MapLibre control escaped.
  @Test
  func mapStyleURLShowsNoCredentialsAndAttributionIsEscaped() {
    let context = _RenderContext(path: [_FiberKey("hardening-map")])
    // mapConfiguration replaces the whole configuration, so it comes before the style modifier.
    let map = Map()
      .mapConfiguration(MapConfiguration(attribution: "<b>x</b> & \"y\""))
      .mapStyle(.custom(url: "https://user:secret@maps.example.test/style.json?token=abc&v=2&X-API-Key=q&signature=s"))
    let node = map._render(in: context)
    #expect(node.attributes["data-map-style-url"] == "https://maps.example.test/style.json?v=2")
    // The forms a browser reads as credentials too, and percent-encoded key names.
    for raw in ["https:user:secret@maps.example.test/s.json", "https:\\\\user:secret@maps.example.test/s.json", " https:/\tuser@maps.example.test/s.json?api%5Fkey=q&v=1"] {
      let styled = Map().mapStyle(.custom(url: raw))._render(in: context)
      let shown = styled.attributes["data-map-style-url"] ?? ""
      #expect(!shown.contains("secret") && !shown.contains("user@") && !shown.contains("api%5Fkey"), "\(raw) -> \(shown)")
    }
    #expect(node.attributes["data-map-attribution"] == "&lt;b&gt;x&lt;/b&gt; &amp; &quot;y&quot;")
  }

  // Item 6a: a camera with NaN or infinite values writes JSON null for them, so the camera JSON stays valid.
  @Test
  func nonFiniteCameraValuesAreWrittenAsNull() {
    let context = _RenderContext(path: [_FiberKey("hardening-camera")])
    let region = CoordinateRegion(
      center: CLLocationCoordinate2D(latitude: .nan, longitude: 1),
      span: CoordinateSpan(latitudeDelta: .infinity, longitudeDelta: 1)
    )
    let node = Map(position: .constant(.region(region)))._render(in: context)
    let camera = node.attributes["data-map-camera"] ?? ""
    #expect(camera.contains("\"latitude\":null"))
    #expect(camera.contains("\"latitudeDelta\":null"))
    #expect(!camera.contains("nan"))
    #expect(!camera.contains("inf"))
  }

  // Item 9: a date outside years 1...9999 is written to the date input at the nearest bound, four digits.
  @Test
  func dateInputYearsStayInTheFourDigitRange() {
    let future = StaticHTMLFiberRenderer().render(DatePicker("Due", selection: .constant(Date(timeIntervalSince1970: 1e12)), displayedComponents: [.date]))
    #expect(future.contains("9999-"))
    #expect(!future.contains("33658-"))
    let past = StaticHTMLFiberRenderer().render(DatePicker("Due", selection: .constant(Date(timeIntervalSince1970: -1e12)), displayedComponents: [.date]))
    #expect(past.contains("0001-"))
  }
}
