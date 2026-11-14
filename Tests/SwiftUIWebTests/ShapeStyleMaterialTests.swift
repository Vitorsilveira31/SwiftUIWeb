import Testing
import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
struct ShapeStyleMaterialTests {
  @Test
  func materialLevelsHaveDistinctTintAndBlur() {
    let materials: [Material] = [.ultraThin, .thin, .regular, .thick, .ultraThick]
    let tints = materials.map(\._swiftUIWebCSSValue)
    let backdrops = materials.map(_materialBackdropFilter)

    #expect(Set(tints).count == materials.count)
    #expect(Set(backdrops).count == materials.count)
    #expect(tints[0].contains("Canvas 28%"))
    #expect(backdrops == [
      "blur(4px) saturate(180%)",
      "blur(8px) saturate(180%)",
      "blur(14px) saturate(180%)",
      "blur(22px) saturate(180%)",
      "blur(30px) saturate(180%)"
    ])
  }

  @Test
  func shapeStyleBackgroundAppliesMaterialWithoutAnExplicitClip() {
    let tree = FiberTree(Text("Glass").background(.ultraThinMaterial))
    let html = tree.renderNode.htmlDescription

    #expect(html.contains("data-background-material=\"ultraThin\""))
    #expect(html.contains("backdrop-filter: blur(4px) saturate(180%)"))
    #expect(html.contains("background: color-mix(in srgb, Canvas 28%, transparent)"))
  }

  @Test
  func erasedAndClippedMaterialsPreserveBackdropBehavior() {
    let erased = AnyShapeStyle(Material.regularMaterial)
    let plainTree = FiberTree(Text("Erased").background(erased))
    #expect(plainTree.renderNode.htmlDescription.contains("blur(14px) saturate(180%)"))

    let clippedTree = FiberTree(
      Text("Clipped").background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16))
    )
    let clippedHTML = clippedTree.renderNode.htmlDescription
    #expect(clippedHTML.contains("data-background-material=\"thick\""))
    #expect(clippedHTML.contains("backdrop-filter: blur(22px) saturate(180%)"))
  }
}
