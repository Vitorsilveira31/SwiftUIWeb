import Testing
import Foundation
import SwiftUIWebCore
import SwiftUIWebFeatures
@testable import SwiftUIWeb

@Suite
@MainActor
final class ScrollViewTests {
  @Test
  func testScrollGeometryModifierEmitsTypedMetadataAndTransformsValues() {
    var values: [(Double, Double)] = []
    let view = ScrollView {
      Text("Large surface")
    }
    .onScrollGeometryChange(for: Double.self, of: { geometry in
      geometry.containerSize.width
    }, action: { _, newValue in
      values.append((newValue, 0))
    })
    let tree = FiberTree(view)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-scroll-geometry-change=\"true\""))
    tree.dispatch(event: "scrollGeometry", value: "0,12,400,1200,320,640,0,12,320,640,0,0,0,0")
    _expectEqual(values.last?.0, 320)
    _expectEqual(values.last?.1, 0)
  }

  @Test
  func testScrollPhaseAndTargetVisibilityCallbacksUseSwiftValues() {
    var phases: [(ScrollPhase, ScrollPhase)] = []
    var visibleIDs: [[Int]] = []
    let view = ScrollView {
      ForEach([1, 2, 3], id: \.self) { Text("\($0)").id($0) }
    }
    .onScrollPhaseChange { old, new in phases.append((old, new)) }
    .onScrollTargetVisibilityChange(idType: Int.self) { visibleIDs.append($0) }
    let tree = FiberTree(view)
    tree.dispatch(event: "scrollPhase", value: "interacting|0,1,300,900,300,400,0,1,300,400,0,0,0,0")
    tree.dispatch(event: "scrollTargetVisibility", value: "1,3")
    _expectEqual(phases.last?.1, .interacting)
    _expectEqual(visibleIDs.last ?? [], [1, 3])
  }

  @Test
  func testScrollTransitionSerializesIdentityAndBoundaryEffects() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Card").scrollTransition(axis: .vertical) { content, phase in
        phase.isIdentity ? content.opacity(1) : content.opacity(0.4).scaleEffect(0.9)
      }
    )
    _expectTrue(html.contains("data-scroll-transition=\"true\""))
    _expectTrue(html.contains("data-scroll-transition-axis=\"vertical\""))
    _expectTrue(html.contains("data-scroll-transition-leading=\"opacity=0.4;transform=scale(0.9,0.9)\""))
  }

  @Test
  func testModernScrollPositionBindingCarriesTargetAndCanBeUpdated() {
    var position = ScrollPosition(id: 2, anchor: .center)
    let binding = Binding<ScrollPosition>(get: { position }, set: { position = $0 })
    let html = StaticHTMLFiberRenderer().render(
      ScrollView { Text("Target").id(2) }.scrollPosition(binding)
    )
    _expectTrue(html.contains("data-scroll-position-id=\"2\""))
    _expectTrue(html.contains("data-scroll-position-anchor=\"0.5,0.5\""))
    let tree = FiberTree(ScrollView { Text("Target").id(2) }.scrollPosition(binding))
    tree.dispatch(event: "scrollPositionUser", value: "")
    // A user scroll answers like SwiftUI: positioned by the user, with no target.
    _expectTrue(position.isPositionedByUser)
    _expectTrue(position.viewID(type: Int.self) == nil)
    _expectTrue(position.point == nil && position.edge == nil)
  }

  @Test
  func testScrollPositionValueEmitsEdgeAndPointTargets() {
    let edge = StaticHTMLFiberRenderer().render(
      ScrollView { Text("Target") }.scrollPosition(.constant(ScrollPosition(idType: Int.self, edge: .bottom)))
    )
    _expectTrue(edge.contains("data-scroll-position-edge=\"bottom\""))
    _expectTrue(!edge.contains("data-scroll-position-point"))

    let point = StaticHTMLFiberRenderer().render(
      ScrollView { Text("Target") }.scrollPosition(.constant(ScrollPosition(idType: Int.self, point: CGPoint(x: 10, y: 20.5))))
    )
    _expectTrue(point.contains("data-scroll-position-point=\"10,20.5\""))
    _expectTrue(!point.contains("data-scroll-position-edge"))

    var x = ScrollPosition(idType: Int.self)
    x.scrollTo(x: 5)
    let horizontal = StaticHTMLFiberRenderer().render(ScrollView { Text("Target") }.scrollPosition(.constant(x)))
    _expectTrue(horizontal.contains("data-scroll-position-point=\"5,\""))

    var y = ScrollPosition(idType: Int.self)
    y.scrollTo(y: 7)
    let vertical = StaticHTMLFiberRenderer().render(ScrollView { Text("Target") }.scrollPosition(.constant(y)))
    _expectTrue(vertical.contains("data-scroll-position-point=\",7\""))
  }

  @Test
  func testScrollPositionEqualityFollowsScrollRequests() {
    // SwiftUI compares two scrollTo requests for the same target as different values.
    var position = ScrollPosition(id: 2)
    _expectTrue(position == ScrollPosition(id: 2))
    position.scrollTo(id: 2)
    _expectTrue(position != ScrollPosition(id: 2))
    var edge = ScrollPosition(idType: Int.self, edge: .top)
    _expectTrue(edge == ScrollPosition(idType: Int.self, edge: .top))
    edge.scrollTo(edge: .top)
    _expectTrue(edge.edge == .top && edge.isPositionedByUser == false)
  }

  @Test
  func testRightToLeftScrollViewDeclaresItsDirection() {
    let html = StaticHTMLFiberRenderer().render(
      ScrollView(.horizontal) { Text("a") }.environment(\.layoutDirection, .rightToLeft)
    )
    _expectTrue(html.contains("dir=\"rtl\""))
    let ltr = StaticHTMLFiberRenderer().render(ScrollView(.horizontal) { Text("a") })
    _expectTrue(!ltr.contains("dir=\"rtl\""))
  }

  @Test
  func testTargetBehaviorAndInitialAnchorRemainSemantic() {
    let html = StaticHTMLFiberRenderer().render(
      ScrollView { Text("One").id(1) }
        .scrollTargetBehavior(.paging)
        .defaultScrollAnchor(.bottom)
    )
    _expectTrue(html.contains("data-scroll-target-behavior=\"paging\""))
    _expectTrue(html.contains("data-scroll-position-initial-anchor=\"0.5,1\""))
    _expectTrue(html.contains("data-default-scroll-anchor=\"0.5,1\""))
  }

  @Test
  func testScrollSurfacesHaveStableSemanticIDsAndIndependentNestedOwners() {
    let html = StaticHTMLFiberRenderer().render(
      ScrollView {
        ScrollView(.horizontal) { Text("inner") }
      }
    )
    let ids = html.split(separator: "data-scroll-id=\"").dropFirst().compactMap { $0.split(separator: "\"").first }
    _expectEqual(ids.count, 2)
    _expectEqual(Set(ids).count, ids.count)
    _expectTrue(html.contains("data-scroll-node=\"true\""))
    _expectTrue(html.contains("data-scroll-axes=\"2\""))
    _expectTrue(html.contains("data-scroll-axes=\"1\""))
  }

  @Test
  func testContentMarginsRemainSemanticForAnchorCoordinator() {
    let html = StaticHTMLFiberRenderer().render(
      ScrollView { Text("content") }
        .contentMargins(.all, EdgeInsets(top: 4, leading: 8, bottom: 12, trailing: 16), for: .scrollContent)
    )
    _expectTrue(html.contains("data-scroll-content-margins=\"4.0,8.0,12.0,16.0\""))
    _expectTrue(html.contains("data-content-margins-placement=\"scrollContent\""))
  }
}
