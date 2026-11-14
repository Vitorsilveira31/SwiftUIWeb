// Embedded/WASI counterpart of Foundation's `Date.ISO8601FormatStyle`,
// `ParseStrategy`, `Date(_:strategy:)` and `Date.ISO8601Format()`, so API
// timestamps parse and print with the same source on every host:
// `try Date(value, strategy: .iso8601)` and `date.ISO8601Format()`.
// Native builds use Foundation's own types.
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

public protocol ParseStrategy {
  associatedtype ParseInput
  associatedtype ParseOutput
  func parse(_ value: ParseInput) throws -> ParseOutput
}

/// Thrown when a string is not an ISO 8601 timestamp the style accepts.
package struct ISO8601ParseError: Error, Hashable, Sendable {
  package let value: String
  package init(value: String) { self.value = value }
}

public extension Date {
  struct ISO8601FormatStyle: SwiftUIWebInternationalization.FormatStyle, ParseStrategy, Hashable, Sendable {
    public var includingFractionalSeconds: Bool
    public var timeZone: TimeZone

    public init(includingFractionalSeconds: Bool = false, timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) {
      self.includingFractionalSeconds = includingFractionalSeconds
      self.timeZone = timeZone
    }

    public func format(_ value: Date) -> String {
      _swiftUIWebFormatISO8601(
        value.timeIntervalSince1970,
        offsetSeconds: timeZone.secondsFromGMT(for: value),
        fractionalSeconds: includingFractionalSeconds
      )
    }

    /// Accepts `YYYY-MM-DDTHH:MM:SS`, optional fractional seconds and a
    /// `Z` or `±HH:MM` offset, like Foundation's `.iso8601` strategy.
    public func parse(_ value: String) throws -> Date {
      guard let seconds = _swiftUIWebParseISO8601(value) else { throw ISO8601ParseError(value: value) }
      return Date(timeIntervalSince1970: seconds)
    }

    public func time(includingFractionalSeconds: Bool) -> Self {
      var copy = self
      copy.includingFractionalSeconds = includingFractionalSeconds
      return copy
    }
  }

  init<S: ParseStrategy>(_ value: S.ParseInput, strategy: S) throws where S.ParseOutput == Date {
    self = try strategy.parse(value)
  }

  func ISO8601Format(_ style: ISO8601FormatStyle = ISO8601FormatStyle()) -> String {
    style.format(self)
  }
}

public extension SwiftUIWebInternationalization.FormatStyle where Self == Date.ISO8601FormatStyle {
  static var iso8601: Date.ISO8601FormatStyle { Date.ISO8601FormatStyle() }
}

public extension ParseStrategy where Self == Date.ISO8601FormatStyle {
  static var iso8601: Date.ISO8601FormatStyle { Date.ISO8601FormatStyle() }
}
