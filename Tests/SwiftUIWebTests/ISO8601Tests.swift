import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// The ISO 8601 arithmetic behind the Embedded `Date.ISO8601FormatStyle`,
/// checked against what Foundation's `.iso8601` strategy parses and prints.
@Suite
@MainActor
struct ISO8601Tests {
  @Test
  func parsesTheTimestampShapesAPIsSend() {
    #expect(_swiftUIWebParseISO8601("2026-09-29T21:05:30Z") == 1_790_715_930)
    #expect(_swiftUIWebParseISO8601("2026-09-29T18:05:30.000-03:00") == 1_790_715_930)
    #expect(_swiftUIWebParseISO8601("2026-09-29T21:05:30.5Z") == 1_790_715_930.5)
    #expect(_swiftUIWebParseISO8601("2026-09-29T21:05:30+00:00") == 1_790_715_930)
    #expect(_swiftUIWebParseISO8601("2026-09-29T23:05:30+0200") == 1_790_715_930)
    #expect(_swiftUIWebParseISO8601("2026-09-29 21:05:30z") == 1_790_715_930)
    #expect(_swiftUIWebParseISO8601("2026-02-28T23:59:59Z") == 1_772_323_199)
    #expect(_swiftUIWebParseISO8601("1969-12-31T23:59:59Z") == -1)
    #expect(_swiftUIWebParseISO8601("2026-09-29T21:05:30") == nil)
    #expect(_swiftUIWebParseISO8601("2026-09-29") == nil)
    #expect(_swiftUIWebParseISO8601("ontem") == nil)
    #expect(_swiftUIWebParseISO8601("2026-02-29T00:00:00Z") == nil)
  }

  @Test
  func rejectsIncompleteOrInvalidTimestamps() {
    for value in [
      "", "ontem", "2026-09-29", "2026-09-29T21:05:30", "2026-13-01T00:00:00Z", "2026-02-29T00:00:00Z",
      "2026-09-29T24:00:00Z", "2026-09-29T21:05:30.Z", "2026-09-29T21:05:30+25:00", "2026-09-29T21:05:30Zjunk",
      "2026/09/29T21:05:30Z",
    ] {
      #expect(_swiftUIWebParseISO8601(value) == nil, "\(value)")
    }
  }

  @Test
  func handlesLeapDaysHourOnlyOffsetsAndMalformedFields() {
    #expect(_swiftUIWebParseISO8601("2024-02-29T00:00:00Z") == 1_709_164_800)
    #expect(_swiftUIWebParseISO8601("2000-02-29T00:00:00Z") == 951_782_400)
    #expect(_swiftUIWebParseISO8601("1900-02-29T00:00:00Z") == nil)
    // `±HH` without minutes is a whole-hour offset.
    #expect(_swiftUIWebParseISO8601("2026-09-29T23:05:30+02") == 1_790_715_930)
    #expect(_swiftUIWebParseISO8601("2026-09-29T21:05:30,25Z") == 1_790_715_930.25)
    for value in [
      "20a6-09-29T21:05:30Z", "2026-09-29T21:05:3xZ", "2026-09-29T21:05:30X", "2026-09-29T21:05:30.5",
      "2026-09-29T21:05:30+0", "2026-09-29T21:05:30+02:6", "2026-09-29T21:05:30+02:60", "2026-00-10T00:00:00Z",
      "2026-04-31T00:00:00Z",
    ] {
      #expect(_swiftUIWebParseISO8601(value) == nil, "\(value)")
    }
  }

  @Test
  func formatsLikeFoundation() {
    #expect(_swiftUIWebFormatISO8601(1_790_715_930) == "2026-09-29T21:05:30Z")
    #expect(_swiftUIWebFormatISO8601(1_790_715_930, fractionalSeconds: true) == "2026-09-29T21:05:30.000Z")
    #expect(_swiftUIWebFormatISO8601(1_790_715_930.5, fractionalSeconds: true) == "2026-09-29T21:05:30.500Z")
    #expect(_swiftUIWebFormatISO8601(1_790_715_930, offsetSeconds: -10_800) == "2026-09-29T18:05:30-03:00")
    #expect(_swiftUIWebFormatISO8601(1_772_323_199) == "2026-02-28T23:59:59Z")
    #expect(_swiftUIWebFormatISO8601(-1) == "1969-12-31T23:59:59Z")
    // The time is truncated, never rounded up to the next second.
    #expect(_swiftUIWebFormatISO8601(0.9996) == "1970-01-01T00:00:00Z")
    #expect(_swiftUIWebFormatISO8601(0.9996, fractionalSeconds: true) == "1970-01-01T00:00:00.999Z")
    #expect(_swiftUIWebFormatISO8601(-0.25, fractionalSeconds: true) == "1969-12-31T23:59:59.750Z")
    #expect(_swiftUIWebFormatISO8601(-62_135_596_800) == "0001-01-01T00:00:00Z")
    #expect(_swiftUIWebFormatISO8601(0, offsetSeconds: 19_800) == "1970-01-01T05:30:00+05:30")
    #expect(_swiftUIWebFormatISO8601(.nan) == "")
  }

  @Test
  func formatsYearsBeforeTheCommonEraAndRejectsOutOfRangeEpochs() {
    // Proleptic Gregorian year -1 (2 BCE) starts 366 + 365 days before 0001.
    #expect(_swiftUIWebFormatISO8601(-62_135_596_800 - 731 * 86_400) == "-0001-01-01T00:00:00Z")
    #expect(_swiftUIWebFormatISO8601(2.0e17) == "")
    #expect(_swiftUIWebFormatISO8601(-.infinity) == "")
  }

  @Test
  func civilArithmeticRoundTrips() {
    for days in [-719_468, -1, 0, 1, 11_016, 20_000, 60_000, 2_932_896] {
      let epoch = Double(days) * 86_400
      #expect(_swiftUIWebParseISO8601(_swiftUIWebFormatISO8601(epoch)) == epoch)
    }
    #expect(_swiftUIWebFormatISO8601(0).hasPrefix("1970-01-01"))
    #expect(_swiftUIWebFormatISO8601(11_016 * 86_400).hasPrefix("2000-02-29"))
  }
}
