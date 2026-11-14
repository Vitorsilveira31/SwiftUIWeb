import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

// These names deliberately remain UNQUALIFIED, exactly like a normal app.
private struct ImportedGeometryLayout: Layout {
  var spacing: CGFloat = 8
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    CGSize(width: proposal.width ?? 100, height: spacing)
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    for view in subviews { view.place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: proposal) }
  }
}

@Suite
@MainActor
final class GeometryCompatibilityTests {
  @Test
  func testFoundationAndSwiftUIWebHaveTheSameGeometryIdentity() {
    let value: CGSize = Foundation.CGSize(width: 40, height: 50)
    let platform: Foundation.CGSize = value
    _expectEqual(platform.width, 40)
    let rect: CGRect = Foundation.CGRect(origin: CGPoint(x: 2, y: 3), size: value)
    _expectEqual(rect.maxX, 42)
    let scalar: CGFloat = Foundation.CGFloat(7)
    _expectEqual(scalar, 7)
  }
  @Test
  func testNormalCustomLayoutSourceRenders() {
    let tree = FiberTree(ImportedGeometryLayout(spacing: 12) { Text("Geometry") })
    _expectTrue(tree.renderNode.htmlDescription.contains("Geometry"))
  }
  @Test
  func testAffineTranslationUsesExistingBasisAndRotationIsNotANoOp() {
    let t = CGAffineTransform.identity.scaledBy(x: 2, y: 3).translatedBy(x: 4, y: 5)
    _expectEqual(Double(t.tx), 8, accuracy: 1e-9)
    _expectEqual(Double(t.ty), 15, accuracy: 1e-9)
    let rotation = CGAffineTransform.identity.rotated(by: .pi / 2)
    _expectEqual(Double(rotation.a), 0, accuracy: 1e-9)
    _expectEqual(Double(rotation.b), 1, accuracy: 1e-9)
  }
}
