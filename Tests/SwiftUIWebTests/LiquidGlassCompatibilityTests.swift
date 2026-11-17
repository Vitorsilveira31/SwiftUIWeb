import Testing
import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// SwiftUI's `glassEffect` family: the browser draws the glass as a backdrop blur, a fill and a hairline edge.
@Suite
@MainActor
struct LiquidGlassRenderingTests {
  @Test
  func glassValuesAreCopiesThatKeepTheirTintAndInteractivity() {
    #expect(Glass.identity == Glass.regular)
    #expect(Glass.clear != Glass.regular)
    #expect(Glass.regular.tint(nil) == Glass.regular)

    let tinted = Glass.clear.tint(.red).interactive()
    #expect(tinted.tintColor == .red)
    #expect(tinted.isInteractive)
    #expect(tinted.isClear)
    #expect(!Glass.clear.interactive(false).isInteractive)
    #expect(Glass.regular.tintColor == nil)
  }

  @Test
  func glassEffectDrawsAThinBlurOverATintedFill() {
    let regular = FiberTree(Text("Glass").glassEffect()).renderNode.htmlDescription
    let clear = FiberTree(Text("Glass").glassEffect(.clear)).renderNode.htmlDescription
    _expectTrue(regular.contains("data-background-material=\"thin\""), regular)
    _expectTrue(regular.contains("backdrop-filter: blur(8px) saturate(180%)"), regular)
    // A clear glass has a fainter fill than the regular one, so the two render differently.
    #expect(regular != clear)

    let tinted = FiberTree(Text("Glass").glassEffect(.regular.tint(.red))).renderNode.htmlDescription
    _expectTrue(tinted != regular, tinted)
  }

  @Test
  func glassEffectClipsToItsShape() {
    let html = FiberTree(Text("Capsule").glassEffect(.regular, in: Capsule())).renderNode.htmlDescription
    _expectTrue(html.contains("Capsule"), html)
    _expectTrue(html.contains("data-background-material=\"thin\""), html)
  }

  @Test
  func glassIdentifiersUnionsAndExtensionsLeaveTheViewAsItIs() {
    let namespace = Namespace()
    let plain = FiberTree(Text("Item")).renderNode.htmlDescription
    #expect(FiberTree(Text("Item").glassEffectID("row", in: namespace.wrappedValue)).renderNode.htmlDescription == plain)
    #expect(FiberTree(Text("Item").glassEffectUnion(id: "row", namespace: namespace.wrappedValue)).renderNode.htmlDescription == plain)
    #expect(FiberTree(Text("Item").backgroundExtensionEffect()).renderNode.htmlDescription == plain)
  }

  @Test
  func glassEffectContainerRendersOnlyItsContent() {
    let grouped = FiberTree(GlassEffectContainer(spacing: 8) { Text("A") }).renderNode.htmlDescription
    #expect(grouped == FiberTree(Text("A")).renderNode.htmlDescription)
  }

  @Test
  func glassButtonStylesReportTheBorderedTokens() {
    #expect(GlassButtonStyle()._swiftUIWebButtonStyleToken == "bordered")
    #expect(GlassProminentButtonStyle()._swiftUIWebButtonStyleToken == "bordered-prominent")

    let plain = FiberTree(Button("Go") {}.buttonStyle(.glass)).renderNode.htmlDescription
    _expectTrue(plain.contains("data-button-style=\"bordered\""), plain)
    let prominent = FiberTree(Button("Go") {}.buttonStyle(.glassProminent)).renderNode.htmlDescription
    _expectTrue(prominent.contains("data-button-style=\"bordered-prominent\""), prominent)
  }

  @Test
  func scrollEdgeEffectIsAnIdentityInTheBrowser() {
    let plain = FiberTree(Text("Edge")).renderNode.htmlDescription
    #expect(FiberTree(Text("Edge").scrollEdgeEffectStyle(.soft, for: .top)).renderNode.htmlDescription == plain)
    #expect(FiberTree(Text("Edge").scrollEdgeEffectStyle(nil, for: .all)).renderNode.htmlDescription == plain)
  }
}

/// Apple-only API that the browser answers with its own values: previews, display scale, system colors and images.
@Suite
@MainActor
struct AppleCompatibilityRenderingTests {
  @Test
  func previewModifiersDoNotChangeTheRenderedView() {
    let plain = FiberTree(Text("Preview")).renderNode.htmlDescription
    let previewed = Text("Preview")
      .previewDisplayName("Light")
      .previewLayout(.sizeThatFits)
      .previewLayout(.fixed(width: 320, height: 200))
      .previewDevice(PreviewDevice(rawValue: "iPhone 17"))
    #expect(FiberTree(previewed).renderNode.htmlDescription == plain)
    #expect(PreviewDevice(rawValue: "iPad") == "iPad")
    #expect(FiberTree(Text("Preview").previewDevice(nil)).renderNode.htmlDescription == plain)
  }

  @Test
  func negatingAnAngleNegatesItsRadians() {
    #expect((-Angle(radians: 1.5)).radians == -1.5)
    #expect((-(-Angle(radians: 0.25))).radians == 0.25)
  }

  @Test
  func displayScaleIsOneUnlessTheHostOverridesIt() {
    var values = EnvironmentValues()
    #expect(values.displayScale == 1)
    values.displayScale = 2
    #expect(values.displayScale == 2)
  }

  @Test
  func imageBuiltFromARenderedViewDrawsThatView() {
    let renderer = ImageRenderer(content: Text("Snapshot"))
    renderer.scale = 2
    let snapshot = renderer.cgImage!
    let labeled = FiberTree(Image(snapshot, scale: 2, label: Text("Snapshot"))).renderNode.htmlDescription
    _expectTrue(labeled.contains("Snapshot"), labeled)
    let decorative = FiberTree(Image(decorative: snapshot, scale: 2)).renderNode.htmlDescription
    _expectTrue(decorative.contains("Snapshot"), decorative)

    // A proposed size frames the rendered view before it becomes the image.
    renderer.proposedSize = ProposedViewSize(width: 40, height: 20)
    let sized = FiberTree(Image(renderer.cgImage!, scale: 1, label: Text("Snapshot"))).renderNode.htmlDescription
    _expectTrue(sized.contains("Snapshot"), sized)
  }

  @Test
  func uiColorSystemValuesResolveToLightAndDarkCSS() {
    #expect(UIColor.systemBackground.css == "light-dark(#FFFFFF, #000000)")
    #expect(UIColor.systemFill.css == "light-dark(rgb(120 120 128 / 0.20), rgb(120 120 128 / 0.36))")
    let all: [UIColor] = [
      .systemBackground, .secondarySystemBackground, .tertiarySystemBackground,
      .systemGroupedBackground, .secondarySystemGroupedBackground, .systemGray5,
      .systemGray6, .lightGray, .systemFill, .secondarySystemFill,
      .tertiarySystemFill, .quaternarySystemFill,
    ]
    #expect(all.allSatisfy { $0.css.hasPrefix("light-dark(") })
  }

  @Test
  func nsColorSystemValuesResolveToLightAndDarkCSS() {
    #expect(NSColor.controlAccentColor.css == "light-dark(#007AFF, #0A84FF)")
    let all: [NSColor] = [
      .windowBackgroundColor, .controlBackgroundColor, .textBackgroundColor,
      .underPageBackgroundColor, .labelColor, .secondaryLabelColor,
      .tertiaryLabelColor, .quaternaryLabelColor, .separatorColor,
      .gridColor, .controlAccentColor, .lightGray,
      .gray, .darkGray, .white, .black, .clear,
    ]
    #expect(all.allSatisfy { $0.css.hasPrefix("light-dark(") })
  }

  @Test
  func colorInitializersCarryTheSystemCSSIntoTheRenderedView() {
    let uiHTML = FiberTree(Text("Tint").background(Color(uiColor: .systemGray5))).renderNode.htmlDescription
    _expectTrue(uiHTML.contains("light-dark(#E5E5EA, #2C2C2E)"), uiHTML)
    let nsHTML = FiberTree(Text("Tint").background(Color(nsColor: .controlAccentColor))).renderNode.htmlDescription
    _expectTrue(nsHTML.contains("light-dark(#007AFF, #0A84FF)"), nsHTML)
  }
}

/// `CGRect` helpers the browser build adds for Foundation-free code.
@Suite
struct FoundationRectGeometryTests {
  @Test
  func rectanglesIntersectOnlyWhenTheyShareInteriorArea() {
    let square = CGRect(x: 0, y: 0, width: 10, height: 10)
    #expect(square.intersects(CGRect(x: 5, y: 5, width: 10, height: 10)))
    // Sharing only an edge is not an intersection.
    #expect(!square.intersects(CGRect(x: 10, y: 0, width: 5, height: 5)))
    #expect(!square.intersects(CGRect(x: 0, y: 10, width: 5, height: 5)))
  }

  @Test
  func unionCoversBothBounds() {
    let union = CGRect(x: 0, y: 0, width: 10, height: 10).union(CGRect(x: 5, y: -5, width: 20, height: 4))
    #expect(union == CGRect(x: 0, y: -5, width: 25, height: 15))
  }

  @Test
  func intersectionIsTheOverlapOrZeroWhenDisjoint() {
    let square = CGRect(x: 0, y: 0, width: 10, height: 10)
    #expect(square.intersection(CGRect(x: 5, y: 5, width: 10, height: 10)) == CGRect(x: 5, y: 5, width: 5, height: 5))
    #expect(square.intersection(CGRect(x: 20, y: 20, width: 1, height: 1)) == .zero)
  }
}
