import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// `Image(decorative:bundle:)`, as in SwiftUI: the image of `Image(_:bundle:)` that assistive technologies skip. In the
/// browser that is an empty `alt`, which also keeps the name from being shown if the image fails to load.
@Suite(.serialized)
@MainActor
struct ImageDecorativeTests {
  @Test
  func aDecorativeImageHasAnEmptyAlt() {
    let source = "data:image/png;base64,iVBORw0KGgo="
    let html = StaticHTMLFiberRenderer().render(Image(decorative: source))
    #expect(html.contains("src=\"\(source)\""), "\(html)")
    #expect(html.contains("alt=\"\""), "\(html)")
    // A named image keeps its name as the text alternative.
    let named = StaticHTMLFiberRenderer().render(Image(source))
    #expect(named.contains("alt=\"\(source)\""), "\(named)")
  }

  @Test
  func aDecorativeCatalogImageLoadsItsAsset() {
    _ImageAssets.install(["Poster": "catalog-assets/Poster.png"])
    defer { _ImageAssets.install(nil) }
    let html = StaticHTMLFiberRenderer().render(Image(decorative: "Poster", bundle: nil))
    #expect(html.contains("src=\"catalog-assets/Poster.png\""), "\(html)")
    #expect(html.contains("alt=\"\""), "\(html)")
  }

  @Test
  func aDecorativeSymbolIsHidden() {
    _ImageAssets.install(["Bolt": "catalog-assets/Bolt.symbol.svg"])
    defer { _ImageAssets.install(nil) }
    let decorative = StaticHTMLFiberRenderer().render(Image(decorative: "Bolt"))
    #expect(decorative.contains("aria-hidden=\"true\""), "\(decorative)")
    #expect(!decorative.contains("role=\"img\""), "\(decorative)")
    let named = StaticHTMLFiberRenderer().render(Image("Bolt"))
    #expect(named.contains("role=\"img\"") && named.contains("aria-label=\"Bolt\""), "\(named)")
  }
}
