@_spi(Renderer) import SwiftUIWebTransferable
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// Private platform boundary. This is presentation, not an alternate Calendar
/// implementation. The WASI Core currently supports Gregorian/ISO dates and
/// fixed offsets; this adapter does not claim IANA/DST calendar arithmetic.
@_spi(Browser) public enum _BrowserDateFormatStyle: UInt32, Sendable {
  case mediumDate = 0, shortTime, mediumDateShortTime
  case longDate, shortPickerTime, secondPickerTime, longDateShortTime, longDateSecondTime
  case monthYear, narrowWeekday
  /// `Intl.DateTimeFormat` options supplied in `_BrowserDateFormatRequest.options`.
  case custom
}

@_spi(Browser) public struct _BrowserDateFormatRequest: Sendable {
  public var epochSeconds: Double
  public var style: _BrowserDateFormatStyle
  public var locale: String
  public var calendar: String
  public var offsetSeconds: Int
  /// `name=value;...` Intl options for `.custom`. `timeZone=local` formats in
  /// the browser's own time zone instead of the fixed `offsetSeconds`.
  public var options: String

  public init(epochSeconds: Double, style: _BrowserDateFormatStyle, locale: String,
              calendar: String = "gregory", offsetSeconds: Int = 0, options: String = "") {
    self.epochSeconds = epochSeconds
    self.style = style
    self.locale = locale
    self.calendar = calendar
    self.offsetSeconds = offsetSeconds
    self.options = options
  }
}

/// Installed before the browser constructs the Scene. Like the UI runtime,
/// installation and formatting are confined to the browser's serial executor.
/// The provider owns no ViewModel or session and invokes native Intl only.
@_spi(Browser) public enum _BrowserDateFormatting {
  public typealias Provider = (_BrowserDateFormatRequest) -> String?
  /// A non-generic holder: storing the closure in a generic `_Locked<Provider?>`
  /// re-abstracts it on every read-modify-write, and in Embedded Swift each
  /// formatting call then wrapped the previous thunk in another one until the
  /// WASM stack overflowed.
  private final class Storage: @unchecked Sendable {
    var provider: Provider = { _ in nil }
    var installed = false
  }
  private static let storage = Storage()
  public static func install(_ value: Provider?) {
    if let value { storage.provider = value; storage.installed = true } else { storage.installed = false }
  }
  public static func format(_ request: _BrowserDateFormatRequest) -> String? {
    guard request.epochSeconds.isFinite, storage.installed else { return nil }
    return storage.provider(request)
  }
}
