import Testing
import Foundation
@testable import SwiftUIWeb
import SwiftUIWebHTML

/// Formats can come from data (a translation, a server string). A width, precision or position they carry is bounded,
/// and a "%" that no conversion follows is text: none of them may trap the browser build, where `Int` is 32 bits.
@Suite
@MainActor
struct FormatFieldLimitTests {
  @Test
  func aPercentSignWithoutAConversionIsText() {
    #expect(String.localizedStringWithFormat("Save 20%!", "x").hasPrefix("Save 20"))
    #expect(String.localizedStringWithFormat("%5", "x") == "%5")
    #expect(String.localizedStringWithFormat("%@ items", "3") == "3 items")
  }

  @Test
  func hugeWidthsAndPrecisionsAreBounded() {
    #expect(String(format: "%99999999999d", 1).count == 100_000)
    #expect(String(format: "%.900000000f", 1.0).count == 100_002)
    #expect(String(format: "%5d|%-4d|%.3f", 42, 7, 2.5) == "   42|7   |2.500")
  }

  @Test
  func translationTemplatesBoundTheirFields() {
    let render = { (view: Text) in StaticHTMLFiberRenderer().render(view) }
    #expect(render(Text("\(0.5, specifier: "%.20f")")).contains("0.50000000000000000000"))
    #expect(render(Text("\(2.25, specifier: "%.2f")")).contains("2.25"))
    // The exact digits of the double, as Foundation writes them: every digit of 1e20, the binary tail of 0.1.
    #expect(render(Text("\(1e20, specifier: "%.2f")")).contains("100000000000000000000.00"))
    #expect(render(Text("\(0.1, specifier: "%.20f")")).contains("0.10000000000000000555"))
    #expect(render(Text("\(-1234.5678, specifier: "%.2f")")).contains("-1234.57"))
    #expect(render(Text("\(0.125, specifier: "%.2f")")).contains("0.12"))
    #expect(render(Text("\(-0.001, specifier: "%.2f")")).contains("-0.00"))
    #expect(render(Text("\(7, specifier: "%05d")")).contains("00007"))
  }
}
