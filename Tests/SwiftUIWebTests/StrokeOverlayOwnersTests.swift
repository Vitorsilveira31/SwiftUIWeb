import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A stroke overlay painted on its base (a box shadow) discards the overlay's rendered layer: what that render
/// registered must not stay registered, render after render.
@Suite
@MainActor
struct StrokeOverlayOwnersTests {
  private struct Outline: View {
    let color: Color
    var body: some View { RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 1) }
  }

  private struct Page: View {
    @State var tick = 0
    let custom: Bool
    var body: some View {
      VStack {
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        Text("card")
          .padding(8)
          .overlay {
            if custom { Outline(color: tick % 2 == 0 ? .red : .blue) } else { RoundedRectangle(cornerRadius: 8).stroke(tick % 2 == 0 ? Color.red : .blue, lineWidth: 1) }
          }
      }
    }
  }

  @Test(arguments: [false, true])
  func renderingAStrokeOverlayAgainKeepsTheRegistrySteady(custom: Bool) {
    let page = Page(custom: custom)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    page.tick = 1
    _ = tree.renderNode
    let settled = tree._registeredOwnerCount
    for tick in 2...21 {
      page.tick = tick
      _ = tree.renderNode
    }
    let html = tree.renderNode.htmlDescription
    #expect(tree._registeredOwnerCount == settled, "owners \(settled) -> \(tree._registeredOwnerCount) (custom: \(custom))")
    #expect(html.contains("box-shadow"), Comment(rawValue: html))
  }

  @Observable final class Palette { var color = Color.red }

  private struct ObservingOutline: View {
    let palette: Palette
    var body: some View { RoundedRectangle(cornerRadius: 8).stroke(palette.color, lineWidth: 1) }
  }

  private struct ObservingPage: View {
    let palette: Palette
    var body: some View {
      Text("card").padding(8).overlay { ObservingOutline(palette: palette) }
    }
  }

  /// The overlay's own view reads the model, its parent does not: a change of the model repaints the stroke, as it
  /// does in SwiftUI.
  @Test
  func aStrokeViewThatObservesAModelRepaintsWhenItChanges() {
    let palette = Palette()
    let tree = FiberTree(VStack { ObservingPage(palette: palette) })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    let before = tree.renderNode.htmlDescription
    palette.color = .blue
    _ = tree.renderNode
    let after = tree.renderNode.htmlDescription
    #expect(before.contains("box-shadow"), "the stroke was not painted on its base: \(before)")
    #expect(before != after, "the stroke did not change: \(after)")
  }
}
