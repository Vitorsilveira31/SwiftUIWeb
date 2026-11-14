import Testing
@testable import SwiftUIWeb
@_spi(Browser) @_spi(Generated) @_spi(Renderer) @testable import SwiftUIWebFeatures
@testable import SwiftUIWebCore
@testable import SwiftUIWebCharts

/// Graphics values an application can receive from data or the page: colors, shadow and detent lengths, symbol angles,
/// text layout runs, font names and chart numbers. None may trap, inject CSS, or write a non-finite number.
@Suite
@MainActor
struct GraphicsValueHardeningTests {
  private func html<V: View>(_ view: V) -> String { StaticHTMLFiberRenderer().render(view) }

  @Test
  func colorStringsThatFetchOrOpenLayersFallBackToClear() {
    #expect(Color("url(x.png)").cssValue == "transparent")
    #expect(Color("image-set(a 1x)").cssValue == "transparent")
    #expect(Color("element(#a)").cssValue == "transparent")
    #expect(Color("red) url(x").cssValue == "transparent")
    #expect(Color("rgb(1,2,3)").cssValue == "rgb(1,2,3)")
    // A custom property whose name holds "image" loads nothing: kept, with its fallback.
    #expect(Color("var(--image-accent, red)").cssValue == "var(--image-accent, red)")
    #expect(Color("IMAGE-SET(a 1x)").cssValue == "transparent")
    #expect(Color("cross-fade(url(a), red)").cssValue == "transparent")
    #expect(Color("red").cssValue == "var(--asset-color-red, red)")
  }

  @Test
  func hoverShadowLengthsAreFinite() {
    let markup = html(Text("x").webHoverShadow(.red, radius: .infinity, y: .nan))
    #expect(!markup.contains("inf") && !markup.contains("nan"))
  }

  @Test
  func wiggleAngleOfANonFiniteValueIsZero() {
    #expect(WiggleSymbolEffect().custom(angle: .nan)._swiftUIWebSymbolEffectName == "wiggle-angle-0")
    #expect(WiggleSymbolEffect().custom(angle: .infinity)._swiftUIWebSymbolEffectName == "wiggle-angle-0")
    #expect(WiggleSymbolEffect().custom(angle: 1e300)._swiftUIWebSymbolEffectName == "wiggle-angle-1000000000")
    #expect(WiggleSymbolEffect().custom(angle: 0.5)._swiftUIWebSymbolEffectName == "wiggle-angle-500")
  }

  @Test
  func nonFiniteDetentsUseTheLargeDetent() {
    #expect(PresentationDetent.fraction(.nan)._cssHeight == "calc(100dvh - 24px)")
    #expect(PresentationDetent.height(.infinity)._cssHeight == "calc(100dvh - 24px)")
    #expect(PresentationDetent.height(.nan)._nominalHeight == 776)
    #expect(PresentationDetent.height(300)._cssHeight == "300.0px")
  }

  @Test
  func textRunWithAnOutOfRangeIndexIsSkipped() {
    // A run index past Int (2^31 in the browser build, 2^63 here) is skipped: converting it would trap.
    let raw = "0,0,100,20\u{1E}L\u{1F}0,0,50,10,2,1\u{1E}R\u{1F}100000000000000000000,0,0,0,10,5,2,1\u{1F}font\u{1F}color"
    let layout = _MeasuredTextLayout(decoding: raw)
    #expect(layout != nil)
    #expect(layout?.lines.first?.runs.isEmpty == true)
  }

  @Test
  func fontFamilyDropsControlCharacters() {
    let markup = html(Text("x").font(.custom("A\u{0C}B\u{7F}C", size: 12)))
    #expect(!markup.contains("\u{0C}") && !markup.contains("\u{7F}"))
  }

  @Test
  func chartNumbersAreFiniteAndBounded() {
    #expect(_chartNumber(.nan) == "0")
    #expect(_chartNumber(.infinity) == "0")
    #expect(_chartNumber(1e300) == "1e+300")
    #expect(_chartNumber(-1.7e308) == "-1.7e+308")
    #expect(_chartNumber(2.5) == "2.5")
  }

  @Test
  func chartCategoryOutsideTheDomainHasNoPlace() {
    let domain = _ChartDomain(lower: -0.5, upper: 1.5, categories: ["a", "b"], categoryMode: true, label: "", reversed: false)
    #expect(domain.knows(.value("", "a")))
    #expect(!domain.knows(.value("", "z")))
    #expect(domain.knows(nil))
  }

  @Test
  func markupRefusesTheStyleElement() {
    #expect(!_isSafeElementName("style"))
    #expect(!_isSafeElementName("STYLE"))
    #expect(_isSafeElementName("section"))
  }
}
