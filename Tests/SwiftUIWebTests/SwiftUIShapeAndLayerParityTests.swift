import Testing
import Foundation
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
import SwiftUIWebHTML
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// Call sites below use the exact spellings Apple SwiftUI accepts; the fact
/// that this file type-checks is part of the contract.
@Suite
@MainActor
struct SwiftUIShapeAndLayerParityTests {
  private func html<V: View>(_ view: V) -> String { StaticHTMLFiberRenderer().render(view) }

  @Test
  func colorValuesResolveToThePaintFormAndViewsToTheLayeredForm() {
    // `Color` is both a View and a ShapeStyle: the paint form wins.
    #expect(html(Text("a").background(Color.red)).contains("background-color: \(Color.red.cssValue)"))
    #expect(html(Text("a").background(.blue)).contains("background-color: \(Color.blue.cssValue)"))
    let gradient = html(Text("g").background(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)))
    #expect(gradient.contains("data-background-style=\"linear-gradient(to right"))
    #expect(!gradient.contains("backdrop-layer\""))
    let dim = html(Text("d").overlay(Color.black.opacity(0.5)))
    #expect(dim.contains("data-layout-kind=\"overlay\""))
    #expect(dim.contains("data-shape-paint=\"color-mix(in srgb, black 50%, transparent)\""))

    // Ordinary views use the value form of the layered modifiers.
    let badge = html(Color.green.frame(width: 80, height: 40).overlay(Text("B"), alignment: .topTrailing))
    #expect(badge.contains("data-layout-kind=\"overlay\""))
    #expect(badge.contains("data-align-x=\"1\"") && badge.contains("data-align-y=\"0\""))
    let outlined = html(Text("o").background(RoundedRectangle(cornerRadius: 8).stroke(.gray, lineWidth: 1)))
    #expect(outlined.contains("data-layout-kind=\"background\""))
    #expect(outlined.contains("data-shape-style=\"stroke\""))
    let aligned = html(Text("t").background(Text("behind"), alignment: .bottomLeading))
    #expect(aligned.contains("data-align-x=\"0\"") && aligned.contains("data-align-y=\"1\""))
  }

  @Test
  func aSidebarSectionsRowsHaveNoGroupedListInset() {
    let sidebar = html(NavigationSplitView {
      List { Section("Donuts") { Text("Top 5") } }
    } detail: { Text("Detail") })
    #expect(sidebar.contains("data-padding-top=\"0\""))
    let grouped = html(List { Section("Donuts") { Text("Top 5") } })
    #expect(grouped.contains("data-padding-top=\"12\""))
  }

  @Test
  func backgroundStyleReachesTheBackgroundsInside() {
    let page = html(Text("tag").background(in: .rect(cornerRadius: 5)).backgroundStyle(.red))
    #expect(page.contains("--swu-background-style:"))
    #expect(page.contains("var(--swu-background-style, var(--color-swu-background))"))
  }

  @Test
  func anOuterBackgroundIsDrawnBehindAnInnerOne() {
    let page = html(Text("page").background(.red).background(.blue))
    // The inner (red) paint is an image layer over the outer (blue) color; neither replaces the other.
    #expect(page.contains("background-image: linear-gradient("))
    #expect(page.contains("background-color:"))
  }

  @Test
  func paintFormsOfOverlayAndBackgroundCoverSwiftUISpellings() {
    #expect(html(Text("p").overlay(.red, in: .capsule)).contains("data-shape=\"capsule\""))
    #expect(html(Text("p").background(.yellow, in: .capsule)).contains("data-background-shape=\"capsule\""))
    #expect(html(Text("p").background(.white, in: .rect(cornerRadius: 8), fillStyle: FillStyle())).contains("data-background-shape=\"rounded-rectangle-8\""))
    #expect(html(Text("p").background(in: .rect(cornerRadius: 4))).contains("data-background-shape=\"rounded-rectangle-4\""))
    #expect(html(Text("p").background()).contains("data-background-style=\"var(--swu-background-style, var(--color-swu-background))\""))
    #expect(html(Text("p").background(.ultraThinMaterial, ignoresSafeAreaEdges: .all)).contains("backdrop-filter"))
  }

  @Test
  func paddedShapeBackgroundsKeepThePaddingNodeAsTheContentLayer() {
    let node = FiberTree(Text("Pill").padding(8).background(.yellow, in: .capsule)).renderNode
    #expect(node.classes == ["backdrop-layer"])
    #expect(node.children.last?.attributes["data-layout-kind"] == "padding")
  }

  @Test
  func contextualShapeStyleMembersTypeCheckInGenericPositions() {
    #expect(html(Circle().fill(.red)).contains("fill: \(Color.red.cssValue)"))
    #expect(html(Circle().stroke(.gray.opacity(0.3), lineWidth: 8)).contains("stroke: color-mix(in srgb, \(Color.gray.cssValue) 30%, transparent)"))
    #expect(html(Text("t").foregroundStyle(.tertiary)).contains("color: var(--tertiary-style, color-mix(in srgb, currentColor 30%, transparent))"))
    #expect(html(Text("t").foregroundStyle(.secondary)).contains("color: var(--secondary-style, color-mix(in srgb, currentColor 60%, transparent))"))
    #expect(html(Circle().fill(.quaternary)).contains("currentColor 18%"))
    #expect(html(Capsule().fill(.tint)).contains("var(--tint-color"))
    #expect(html(Text("t").foregroundStyle(.linearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))).contains("background-clip: text"))
    #expect(html(Rectangle().fill(.radialGradient(colors: [.white, .black], center: .center, startRadius: 0, endRadius: 20))).contains("<radialGradient"))
    #expect(html(Rectangle().fill(.separator)).contains("var(--color-swu-border)"))
    #expect(html(Text("t").foregroundStyle(.foreground)).contains("color: currentColor"))
  }

  @Test
  func unevenRoundedRectangleDrawsPerCornerGeometryAndLogicalCSSRadii() {
    let shape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomTrailingRadius: 4)
    #expect(shape.style == .continuous)
    #expect(shape.cornerRadii == RectangleCornerRadii(topLeading: 16, bottomTrailing: 4))
    let path = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 40))._svgPathData
    #expect(path.hasPrefix("M 16 0 L 100 0 L 100 36 C"))
    #expect(path.contains("L 0 40 L 0 16 C"))
    // Radii are clamped to half of the shorter side.
    let clamped = Path(roundedRect: CGRect(x: 0, y: 0, width: 20, height: 10), cornerRadii: RectangleCornerRadii(topLeading: 50))
    #expect(clamped._svgPathData.hasPrefix("M 5 0"))
    #expect(shape.inset(by: 2).cornerRadii == shape.cornerRadii)
    #expect(shape.inset(by: 2)._insetRadii.topLeading == 14)

    let filled = html(shape.fill(.orange).frame(width: 100, height: 40))
    #expect(filled.contains("data-shape=\"uneven-rounded-rectangle\""))
    let clipped = html(Color.purple.clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12)))
    #expect(clipped.contains("border-start-start-radius: 12px"))
    #expect(clipped.contains("border-start-end-radius: 12px"))
    #expect(clipped.contains("border-end-end-radius: 0px"))
    #expect(clipped.contains("data-clip-shape=\"uneven-rounded-rectangle\""))
    let radii = RectangleCornerRadii(topLeading: 1, bottomLeading: 2, bottomTrailing: 3, topTrailing: 4)
    #expect(html(Text("b").background(.blue, in: .rect(cornerRadii: radii))).contains("border-end-start-radius: 2px"))
  }

  @Test
  func contextualShapeMembersMatchSwiftUI() {
    #expect(html(Color.red.clipShape(.circle)).contains("data-clip-shape=\"circle\""))
    #expect(html(Color.red.clipShape(.rect)).contains("data-clip-shape=\"rectangle\""))
    #expect(html(Color.red.clipShape(.capsule(style: .continuous))).contains("data-clip-shape=\"capsule\""))
    #expect(html(Color.red.clipShape(.ellipse)).contains("data-clip-shape=\"ellipse\""))
    let radius: CGFloat = 6
    #expect(html(Color.red.clipShape(.rect(cornerRadius: radius))).contains("border-radius: 6px"))
    #expect(html(Color.red.clipShape(.rect(cornerSize: CGSize(width: 5, height: 5)))).contains("border-radius: 5px"))
    #expect(html(Text("hit").contentShape(.rect)).contains("data-content-shape=\"rectangle\""))
    #expect(html(Text("hit").contentShape(.rect(cornerRadius: 8))).contains("data-content-shape=\"rounded-rectangle\""))
    #expect(html(Text("hit").contentShape(.rect(topLeadingRadius: 8))).contains("data-content-shape=\"uneven-rounded-rectangle\""))
  }

  @Test
  func trimmedShapesCarryAnimatableDashGeometryWithoutDynamicCasts() {
    let ring = html(Circle().trim(from: 0, to: 0.25).stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round)).frame(width: 48, height: 48))
    #expect(ring.contains("data-trim-from=\"0\""))
    #expect(ring.contains("data-trim-to=\"0.25\""))
    #expect(ring.contains("pathLength=\"1\""))
    #expect(ring.contains("stroke-dasharray: 0.25 0.75"))
    #expect(ring.contains("data-shape=\"circle\""))
    // Like Core Graphics, an ellipse starts at angle 0 (trailing midpoint)
    // and runs clockwise, so trim(0, 0.25) spans 3 to 6 o'clock.
    #expect(Path(ellipseIn: CGRect(x: 0, y: 0, width: 48, height: 48))._svgPathData.hasPrefix("M 48 24 A 24 24 0 1 1 0 24"))
    let adapter = Circle().trim(from: 0.1, to: 0.6)._swiftUIWebShapeAdapter
    #expect(adapter?.trimFrom == 0.1 && adapter?.trimTo == 0.6)
    #expect(Circle()._swiftUIWebShapeAdapter == nil)
  }

  @Test
  func zIndexEmitsValidIntegerCSS() {
    let whole = html(Text("z").zIndex(2))
    #expect(whole.contains("z-index: 2") && !whole.contains("z-index: 2."))
    let fraction = html(Text("z").zIndex(0.5))
    #expect(fraction.contains("z-index: 1") && !fraction.contains("z-index: 0."))
    #expect(html(Text("z").zIndex(-1.5)).contains("z-index: -2"))
  }
}
