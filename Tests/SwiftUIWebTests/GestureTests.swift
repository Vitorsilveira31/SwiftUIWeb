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
final class GestureTests {
  @Test
  func testGestureValuesExposeSwiftUIShapedConfiguration() {
    let drag = DragGesture(minimumDistance: 4, coordinateSpace: .global)
    _expectEqual(drag.minimumDistance, 4)
    _expectEqual(drag.coordinateSpace, .global)
    _expectEqual(MagnifyGesture(minimumScaleDelta: 0.05).minimumScaleDelta, 0.05)
    _expectEqual(RotateGesture(minimumAngleDelta: .degrees(3)).minimumAngleDelta, .degrees(3))
    _expectEqual(LongPressGesture(minimumDuration: 1, maximumDistance: 20).minimumDuration, 1)
  }

  @Test
  func testTapCountAndGestureMaskUseSwiftUIOptionSetSemantics() {
    let gesture = TapGesture(count: 2).onEnded {}
    let html = StaticHTMLFiberRenderer().render(
      Text("Double tap").gesture(gesture, including: [.gesture, .subviews])
    )
    _expectTrue(html.contains("count=2"))
    _expectTrue(html.contains("data-gesture-mask=\"all\""))
    _expectEqual(GestureMask(rawValue: 2), .subviews)
    _expectEqual(GestureMask(rawValue: 0), .none)
  }

  @Test
  func testDragCallbacksReceiveCoalescedValueAndEnd() {
    var changed: [Double] = []
    var ended: [Double] = []
    let view = Text("Drag").gesture(
      DragGesture(minimumDistance: 5)
        .onChanged { changed.append($0.translation.width) }
        .onEnded { ended.append($0.translation.width) }
    )
    let tree = FiberTree(view)
    let changedEvent = try! _require(tree.renderNode.events.keys.first(where: { $0.hasSuffix("-changed") }))
    let endedEvent = try! _require(tree.renderNode.events.keys.first(where: { $0.hasSuffix("-ended") }))
    tree.dispatch(event: changedEvent, value: "24,8,4,8,24,8,0,0,0")
    tree.dispatch(event: endedEvent, value: "30,8,4,8,30,8,0,0,0")
    _expectEqual(changed, [20])
    _expectEqual(ended, [26])
    _expectTrue(tree.renderNode.htmlDescription.contains("data-gesture-descriptor"))
    _expectTrue(tree.renderNode.htmlDescription.contains("space=local"))
  }

  @Test
  func testGestureStateUpdatingAndCancellationReset() {
    var state = GestureState<Int>(wrappedValue: 0)
    let gesture = DragGesture(minimumDistance: 0).updating(state) { value, current, _ in
      current = Int(value.translation.width)
    }
    let tree = FiberTree(Text("State").gesture(gesture))
    let changedEvent = try! _require(tree.renderNode.events.keys.first(where: { $0.hasSuffix("-changed") }))
    let endedEvent = try! _require(tree.renderNode.events.keys.first(where: { $0.hasSuffix("-ended") }))
    tree.dispatch(event: changedEvent, value: "10,0,0,0,10,0,0,0,0")
    _expectEqual(state.wrappedValue, 10)
    let cancelledEvent = try! _require(tree.renderNode.events.keys.first(where: { $0.hasSuffix("-cancelled") }))
    tree.dispatch(event: cancelledEvent, value: "cancelled")
    _expectEqual(state.wrappedValue, 0)
    tree.dispatch(event: changedEvent, value: "10,0,0,0,10,0,0,0,0")
    tree.dispatch(event: endedEvent, value: "10,0,0,0,10,0,0,0,0")
    _expectEqual(state.wrappedValue, 0)
  }

  @Test
  func testMagnifyAndRotateDecodeValues() {
    var scale = 0.0
    var angle = Angle.zero
    let view = VStack {
      Text("Zoom").gesture(MagnifyGesture().onChanged { scale = $0.magnification })
      Text("Rotate").gesture(RotateGesture().onEnded { angle = $0.rotation })
    }
    let tree = FiberTree(view)
    var allEvents: [(String, _EventHandler)] = []
    func collect(_ node: _RenderNode) { allEvents.append(contentsOf: node.events.map { ($0.key, $0.value) }); for child in node.children { collect(child) } }
    collect(tree.renderNode)
    let events = allEvents
    let magnify = try! _require(events.first(where: { $0.0.contains("magnify") && $0.0.hasSuffix("-changed") })?.0)
    let rotate = try! _require(events.first(where: { $0.0.contains("rotate") && $0.0.hasSuffix("-ended") })?.0)
    tree.dispatch(event: magnify, value: "1.25,1,0,0,0,0,10,10")
    tree.dispatch(event: rotate, value: "0.5,0,0,0,0,0,10,10")
    _expectEqual(scale, 1.25)
    _expectEqual(angle.radians, 0.5)
  }

  @Test
  func testGestureCompositionAndPriorityAreSerialized() {
    let composed = DragGesture().simultaneously(with: MagnifyGesture())
    let html = StaticHTMLFiberRenderer().render(
      Text("Compose")
        .gesture(composed)
        .highPriorityGesture(TapGesture(count: 2).onEnded {})
    )
    _expectTrue(html.contains("composition=simultaneous"))
    _expectTrue(html.contains("data-gesture-priority=\"high\""))
    _expectTrue(html.contains("data-gesture-descriptors"))
  }

  @Test
  func testSequencedAndExclusiveGesturesKeepCompositionMetadata() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Text("Sequence").gesture(TapGesture().sequenced(before: LongPressGesture()))
        Text("Exclusive").gesture(DragGesture().exclusively(before: TapGesture()))
      }
    )
    _expectTrue(html.contains("composition=sequenced"))
    _expectTrue(html.contains("composition=exclusive"))
    _expectTrue(html.contains("kind=longpress"))
    _expectTrue(html.contains("kind=drag"))
  }

  @Test
  func testNestedCompositionDescriptorsRemainRecursive() {
    let nested = DragGesture(minimumDistance: 4)
      .simultaneously(with: MagnifyGesture(minimumScaleDelta: 0.08))
      .sequenced(before: TapGesture(count: 2))
    let html = StaticHTMLFiberRenderer().render(Text("Nested").gesture(nested))
    _expectTrue(html.contains("composition=sequenced"))
    _expectTrue(html.contains("composition=simultaneous"))
    _expectTrue(html.contains("minScale=0.08"))
    _expectTrue(html.contains("count=2"))
  }

  @Test
  func testTypedSequenceAndExclusiveValuesDecodeChildPayloads() {
    var sequenceReachedSecond = false
    let sequence = TapGesture().sequenced(before: LongPressGesture()).onEnded { value in
      if case .second(_, let second) = value, second == true { sequenceReachedSecond = true }
    }
    let sequenceTree = FiberTree(Text("Sequence").gesture(sequence))
    let sequenceEnded = try! _require(sequenceTree.renderNode.events.keys.first(where: { $0.hasSuffix("-ended") }))
    sequenceTree.dispatch(event: sequenceEnded, value: "longpress|true")
    _expectTrue(sequenceReachedSecond)

    var dragWon = false
    let exclusive = TapGesture().exclusively(before: DragGesture(minimumDistance: 0)).onEnded { value in
      if case .second = value { dragWon = true }
    }
    let exclusiveTree = FiberTree(Text("Exclusive").gesture(exclusive))
    let exclusiveEnded = try! _require(exclusiveTree.renderNode.events.keys.first(where: { $0.hasSuffix("-ended") }))
    exclusiveTree.dispatch(event: exclusiveEnded, value: "drag|10,0,0,0,10,0,10,0,0")
    _expectTrue(dragWon)
  }

  @Test
  func testComposedValueTagsRouteToTheMatchingChild() {
    var translation = 0.0
    var magnification = 0.0
    let gesture = DragGesture(minimumDistance: 0)
      .onChanged { translation = $0.translation.width }
      .simultaneously(with: MagnifyGesture().onChanged { magnification = $0.magnification })
    let tree = FiberTree(Text("Compose").gesture(gesture))
    let changed = try! _require(tree.renderNode.events.keys.first(where: { $0.hasSuffix("-changed") }))
    tree.dispatch(event: changed, value: "drag|12,0,2,0,12,0,12,0,0")
    _expectEqual(translation, 10)
    _expectEqual(magnification, 0)
    tree.dispatch(event: changed, value: "magnify|1.4,1,0,0,0,0,4,4")
    _expectEqual(magnification, 1.4)
  }

  @Test
  func testIndependentSimultaneousModifierKeepsEachDescriptor() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Both")
        .gesture(DragGesture(minimumDistance: 3).onChanged { _ in })
        .simultaneousGesture(TapGesture().onEnded {})
    )
    _expectTrue(html.contains("data-gesture-priorities=\"normal,simultaneous\""))
    _expectTrue(html.contains("kind=drag"))
    _expectTrue(html.contains("kind=tap"))
  }

  @Test
  func testProjectedGestureStateUsesSwiftUIValueSpelling() {
    struct ProjectedView: View {
      @GestureState var isPressed = false
      var body: some View {
        Text("Press").gesture(
          LongPressGesture(minimumDuration: 0)
            .updating($isPressed) { value, state, transaction in
              state = value
              transaction.disablesAnimations = true
            }
            .onEnded { _ in }
        )
      }
    }
    let tree = FiberTree(ProjectedView())
    let changed = try! _require(tree.renderNode.events.keys.first(where: { $0.hasSuffix("-changed") }))
    tree.dispatch(event: changed, value: "true")
    _expectNotNil(tree.renderNode.attributes["data-gesture-descriptor"])
  }

  @Test
  func testCoordinateSpaceAndThresholdMetadataSurviveErasure() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Local").gesture(
        DragGesture(minimumDistance: 2, coordinateSpace: .named("surface"))
          .onEnded { _ in }
      )
    )
    _expectTrue(html.contains("space=named:surface"))
    _expectTrue(html.contains("minDistance=2"))
    _expectTrue(html.contains("data-gesture-coordinate-space=\"named:surface\""))
  }

  @Test
  func testLongPressGestureStillUsesExistingCompatibilityBridge() {
    var states: [Bool] = []
    var ended = 0
    let tree = FiberTree(Text("Press").onLongPressGesture(minimumDuration: 0, perform: { ended += 1 }, onPressingChanged: { states.append($0) }))
    tree.dispatch(event: "pointerdown")
    tree.dispatch(event: "pointerup")
    _expectEqual(states, [true, false])
    _expectEqual(ended, 1)
  }
}
