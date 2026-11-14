import Testing
@_spi(Browser) import SwiftUIWebInternationalization

@Suite(.serialized)
@MainActor
struct BrowserDateFormattingTests {
  @Test
  func providerIsOptionalAndReceivesExplicitUnits() {
    _BrowserDateFormatting.install(nil)
    _expectNil(_BrowserDateFormatting.format(.init(epochSeconds: 0, style: .mediumDate, locale: "pt_BR")))
    var observed: _BrowserDateFormatRequest?
    _BrowserDateFormatting.install { request in observed = request; return "date" }
    defer { _BrowserDateFormatting.install(nil) }
    let request = _BrowserDateFormatRequest(epochSeconds: 86_400, style: .monthYear, locale: "pt_BR", offsetSeconds: -10_800)
    _expectEqual(_BrowserDateFormatting.format(request), "date")
    _expectEqual(observed?.epochSeconds, 86_400)
    _expectEqual(observed?.offsetSeconds, -10_800)
    _expectNil(_BrowserDateFormatting.format(.init(epochSeconds: .infinity, style: .mediumDate, locale: "pt_BR")))
  }
}
