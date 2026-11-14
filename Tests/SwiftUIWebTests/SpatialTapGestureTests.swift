import Testing
import Foundation
@testable import SwiftUIWeb
import SwiftUIWebCore
import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
struct SpatialTapGestureTests {
  @Test
  func spatialTapReportsTheLocationTheHostSends() {
    var locations: [CGPoint] = []
    let tree = FiberTree(Text("Tap").gesture(SpatialTapGesture().onEnded { locations.append($0.location) }))
    let endedEvent = try! _require(tree.renderNode.events.keys.first(where: { $0.hasSuffix("-ended") }))
    tree.dispatch(event: endedEvent, value: "12.5,34")
    _expectEqual(locations, [CGPoint(x: 12.5, y: 34)])
  }

  @Test
  func spatialTapWithoutAPositionFallsBackToTheZeroPoint() {
    var locations: [CGPoint] = []
    let tree = FiberTree(Text("Tap").gesture(SpatialTapGesture().onEnded { locations.append($0.location) }))
    let endedEvent = try! _require(tree.renderNode.events.keys.first(where: { $0.hasSuffix("-ended") }))
    tree.dispatch(event: endedEvent, value: "")
    _expectEqual(locations, [CGPoint(x: 0, y: 0)])
  }
}
