import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// A catalog image drawn for a denser screen is laid out at its size in points on every screen, from the size the asset
/// compiler read (`SWIFTUIWEB_IMAGE_SIZES`), before its file loads.
@Suite(.serialized)
@MainActor
struct ImageAssetPointSizeTests {
  @Test
  func aDenseCatalogImageIsLaidOutAtItsSizeInPoints() {
    _ImageAssets.install(["Poster": "catalog-assets/@2x/Poster.png", "Plain": "catalog-assets/Plain.png"])
    _ImageAssets.install(sizes: "Poster=100x50")
    defer { _ImageAssets.install(nil) }
    let dense = StaticHTMLFiberRenderer().render(Image("Poster"))
    #expect(dense.contains("width=\"100\""), "\(dense)")
    #expect(dense.contains("height=\"50\""), "\(dense)")
    let plain = StaticHTMLFiberRenderer().render(Image("Plain"))
    #expect(!plain.contains("width=\""), "\(plain)")
  }

  @Test
  func clearingTheAssetsClearsTheirSizes() {
    _ImageAssets.install(sizes: "Poster=100x50")
    _ImageAssets.install(nil)
    #expect(_ImageAssets.pointSize(of: "Poster") == nil)
  }
}
