import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@testable import SwiftUIWeb

/// `Image("Name")` renders the file the build copied for that asset-catalog
/// image set once the host installed the generated manifest; a name without
/// an entry is a file path of the app, and a remote URL needs `Image(_:alt:)`.
@Suite(.serialized)
@MainActor
struct ImageAssetsTests {
  private func source<V: View>(_ view: V) -> String? {
    FiberTree(view).renderNode.attributes["src"]
  }

  @Test
  func assetNamesResolveThroughTheInstalledManifest() {
    _ImageAssets.install(manifest: "AppBrand=catalog-assets/AppBrand.svg;Poster=catalog-assets/Poster.png;=bad;Broken;")
    defer { _ImageAssets.install(nil) }
    #expect(_ImageAssets.resolve("AppBrand") == "catalog-assets/AppBrand.svg")
    #expect(_ImageAssets.resolve("Poster") == "catalog-assets/Poster.png")
    #expect(_ImageAssets.resolve("Broken") == nil)
    #expect(source(Image("AppBrand")) == "catalog-assets/AppBrand.svg")
    #expect(source(Image("AppBrand", bundle: nil)) == "catalog-assets/AppBrand.svg")
    #expect(source(Image("media/cover.jpg")) == "media/cover.jpg")
    #expect(source(Image("https://example.test/a.png", alt: "a")) == "https://example.test/a.png")
  }

  @Test
  func withoutAManifestNamesStayLiteral() {
    _ImageAssets.install(nil)
    #expect(_ImageAssets.isEmpty)
    #expect(source(Image("AppBrand")) == "AppBrand")
  }
}
