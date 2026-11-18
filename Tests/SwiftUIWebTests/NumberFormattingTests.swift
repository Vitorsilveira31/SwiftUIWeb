import Testing
@testable import SwiftUIWebInternationalization
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// The decimal text handed to the browser's `Intl.NumberFormat` behind the
/// Embedded `FloatingPointFormatStyle` and `IntegerFormatStyle`. The
/// formatting itself (currency, percent, locales, precision, rounding) is
/// checked in `Tools/test-text-format.mjs`.
@Suite(.serialized)
@MainActor
struct NumberFormattingTests {
  @Test
  func decimalTextOfValuesIsTheShortestRoundTripForm() {
    #expect(_swiftUIWebDecimalText(28300.4) == "28300.4")
    #expect(_swiftUIWebDecimalText(1e21) == "1e+21")
    #expect(_swiftUIWebDecimalText(Float(0.5)) == "0.5")
    #expect(_swiftUIWebDecimalText(-28300) == "-28300")
    #expect(_swiftUIWebDecimalText(UInt64.max) == "18446744073709551615")
    #expect(_swiftUIWebDecimalText(Double.nan) == "nan")
    #expect(_swiftUIWebDecimalText(-Double.infinity) == "-inf")
    #expect(_swiftUIWebDecimalText(0.1 + 0.2) == "0.30000000000000004")
  }

  @Test
  func theBrowserFormatsAndAnAnswerlessOneLeavesThePlainText() {
    #expect(_swiftUIWebFormatNumber("1.5", options: "style=hex") == "1.5")
    let swiftFormatter = _TextHost.formatNumber
    // The fake browser is global while it is installed: it answers and records only this test's values, so the
    // suites that format numbers at the same time on other threads still get the Swift answer.
    var asked: [String] = []
    _TextHost.formatNumber = { text, options in
      guard text == "424242" || text == "abc" else { return swiftFormatter?(text, options) }
      asked.append("\(text) \(options)")
      return text == "424242" ? "quatrocentos" : nil
    }
    defer { _TextHost.formatNumber = swiftFormatter }
    #expect(_swiftUIWebFormatNumber("424242", options: "locale=pt_BR") == "quatrocentos")
    #expect(_swiftUIWebFormatNumber("abc", options: "") == "abc")
    #expect(asked == ["424242 locale=pt_BR", "abc "])
  }

  @Test
  func theCurrentLocaleIsTheVisitorsAndANamedOneIsKept() {
    let swiftFormatter = _TextHost.formatNumber
    var asked: [String] = []
    _TextHost.formatNumber = { text, options in
      guard text == "3000000007" else { return swiftFormatter?(text, options) }
      asked.append(options)
      return nil
    }
    defer { _TextHost.formatNumber = swiftFormatter }
    _ = IntegerFormatStyle<Int>().format(3_000_000_007)
    _ = IntegerFormatStyle<Int>(locale: Locale(identifier: "en_US_POSIX")).format(3_000_000_007)
    _ = IntegerFormatStyle<Int>().locale(Locale(identifier: "pt_BR")).format(3_000_000_007)
    // Locale.current hands the browser its own locale (the visitor's); a locale named by the app is passed as named.
    #expect(asked.count == 3)
    #expect(asked[0].contains("locale=;") || asked[0].hasSuffix("locale="))
    #expect(asked[1].contains("locale=en_US_POSIX"))
    #expect(asked[2].contains("locale=pt_BR"))
    // They format differently, so they are different values (Apple's current locale is not a named one either).
    #expect(Locale.current != Locale(identifier: "en_US_POSIX"))
    #expect(Locale.current.identifier == "en_US_POSIX")
  }

  @Test
  func compactNotationKeepsOrdinaryText() {
    #expect(_swiftUIWebCompactNumberText(999) == nil)
    #expect(_swiftUIWebCompactNumberText(1_234) == "1.2K")
    #expect(_swiftUIWebCompactNumberText(12_345) == "12K")
    #expect(_swiftUIWebCompactNumberText(-1_500_000) == "-1.5M")
    #expect(_swiftUIWebCompactNumberText(1e15) == "1000T")
    #expect(_swiftUIWebCompactNumberText(1e30) == "1" + String(repeating: "0", count: 18) + "T")
  }

  /// Int64(Double) traps for a scaled value at or above 2^63 (about 9.22e30) and for infinity. Such values
  /// have no compact form here, so they fall back to the full text the caller already has.
  @Test
  func compactNotationDoesNotTrapOnHugeOrNonFiniteValues() {
    #expect(_swiftUIWebCompactNumberText(.infinity) == nil)
    #expect(_swiftUIWebCompactNumberText(-.infinity) == nil)
    #expect(_swiftUIWebCompactNumberText(.nan) == nil)
    #expect(_swiftUIWebCompactNumberText(9.0e30)?.hasSuffix("T") == true)
    #expect(_swiftUIWebCompactNumberText(1e31) == nil)
    #expect(_swiftUIWebCompactNumberText(-1e31) == nil)
    #expect(_swiftUIWebCompactNumberText(.greatestFiniteMagnitude) == nil)
  }
}
