import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A shadow on a rounded, clipped card (with an overlay stroke) must follow the rounded corners: the node that
/// carries the `box-shadow` gets the clip's radius, so no rectangle shows around the card.
@Suite
@MainActor
struct ShadowFollowsClippedShapeTests {
  private func shadowNode(in node: _RenderNode) -> _RenderNode? {
    if node.styles["box-shadow"] != nil { return node }
    for child in node.children { if let found = shadowNode(in: child) { return found } }
    return nil
  }

  @Test func overlayWrapperShadowInheritsTheClipRadius() throws {
    let tree = FiberTree(
      Color.red
        .frame(width: 100, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white, lineWidth: 1))
        .shadow(color: .black, radius: 10, x: 1, y: 0)
    )
    let carrier = try #require(shadowNode(in: tree.renderNode))
    #expect(carrier.styles["border-radius"] == "20px")
  }

  @Test func plainBoxShadowKeepsNoRadius() throws {
    let tree = FiberTree(Color.red.frame(width: 100, height: 120).shadow(color: .black, radius: 10, x: 0, y: 2))
    let carrier = try #require(shadowNode(in: tree.renderNode))
    #expect(carrier.styles["border-radius"] == nil)
  }
}
