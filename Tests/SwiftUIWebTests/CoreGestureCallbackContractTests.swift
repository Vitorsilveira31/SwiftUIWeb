import Testing
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite
@MainActor
struct CoreGestureCallbackContractTests {
  @Test
  func dragAndTransformGestureCallbacksComposeAndResetTheirState() {
    var dragEvents: [String] = []
    let drag = DragGesture(minimumDistance: 0)
      .onChanged { dragEvents.append("first:\($0.translation.width)") }
      .onChanged { dragEvents.append("second:\($0.translation.width)") }
      .onEnded { dragEvents.append("end:\($0.translation.width)") }
    let erasedDrag = _eraseGesture(drag)
    erasedDrag.actionBox.changed?("1,2,0,0,7,8,9,10,11")
    erasedDrag.actionBox.ended?("3,4,0,0,5,6,7,8,9")
    erasedDrag.actionBox.endedAction?()
    #expect(dragEvents == ["first:1.0", "second:1.0", "end:3.0", "end:0.0"])

    let identical = MagnifyGesture.Value(magnification: 2, startMagnification: 1.5, velocity: 0.25)
    #expect(identical == MagnifyGesture.Value(magnification: 2, startMagnification: 1.5, velocity: 0.25))
    #expect(identical != MagnifyGesture.Value(magnification: 2.1, startMagnification: 1.5, velocity: 0.25))
    #expect(identical == identical)

    var magnifyEvents: [String] = []
    let magnify = MagnifyGesture()
      .onChanged { magnifyEvents.append("changed-1:\($0.magnification)") }
      .onChanged { magnifyEvents.append("changed-2:\($0.magnification)") }
      .onEnded { magnifyEvents.append("ended:\($0.magnification)") }
    let erasedMagnify = _eraseGesture(magnify)
    erasedMagnify.actionBox.changed?("2.5,2,0.5,10,3,4,5,6")
    erasedMagnify.actionBox.ended?("3.5")
    erasedMagnify.actionBox.endedAction?()
    #expect(magnifyEvents == ["changed-1:2.5", "changed-2:2.5", "ended:3.5", "ended:1.0"])

    var angleState = GestureState(wrappedValue: Angle.zero)
    let rotate = RotateGesture().updating(angleState) { value, current, transaction in
      current = value.rotation
      transaction.disablesAnimations = true
    }
    let erasedRotate = _eraseGesture(rotate)
    erasedRotate.actionBox.changed?("0.75,0.5,0.1,12,1,2,3,4")
    #expect(angleState.wrappedValue == .radians(0.75))
    erasedRotate.actionBox.reset?()
    #expect(angleState.wrappedValue == .zero)
  }

  @Test
  func simultaneousSequenceAndExclusiveCallbacksRouteTypedChildValues() {
    var simultaneousEvents: [String] = []
    let simultaneous = TapGesture().simultaneously(with: DragGesture())
      .onChanged { value in
      simultaneousEvents.append("change:\(value.first == nil):\(value.second?.translation.width ?? -1)")
      }
      .onChanged { value in simultaneousEvents.append("again:\(value.second != nil)") }
      .onEnded { value in simultaneousEvents.append("end:\(value.first == nil):\(value.second != nil)") }
    let erasedSimultaneous = _eraseGesture(simultaneous)
    erasedSimultaneous.actionBox.changed?("drag|8,2,0,0,8,2,0,0,0")
    erasedSimultaneous.actionBox.changed?("tap|")
    erasedSimultaneous.actionBox.ended?("tap|")
    erasedSimultaneous.actionBox.endedAction?()
    #expect(simultaneousEvents == [
      "change:true:8.0", "again:true", "change:false:-1.0", "again:false",
      "end:false:false", "end:true:false"
    ])

    var sequenceValues: [String] = []
    let sequence = TapGesture().sequenced(before: DragGesture())
      .onChanged { value in
        switch value {
        case .first: sequenceValues.append("first")
        case .second: sequenceValues.append("second")
        }
      }
      .onChanged { _ in sequenceValues.append("also-changed") }
      .onEnded { value in
        if case .second(_, let drag?) = value { sequenceValues.append("ended:\(drag.translation.width)") }
      }
    let erasedSequence = _eraseGesture(sequence)
    erasedSequence.actionBox.changed?("tap|")
    erasedSequence.actionBox.changed?("drag|10,0,0,0,10,0,0,0,0")
    erasedSequence.actionBox.ended?("drag|12,0,0,0,12,0,0,0,0")
    erasedSequence.actionBox.reset?()
    erasedSequence.actionBox.endedAction?()
    #expect(sequenceValues == [
      "first", "also-changed", "second", "also-changed", "ended:12.0", "ended:0.0"
    ])

    var exclusiveValues: [String] = []
    let exclusive = TapGesture().exclusively(before: DragGesture())
      .onChanged { value in
        switch value {
        case .first: exclusiveValues.append("first")
        case .second(let drag): exclusiveValues.append("second:\(drag.translation.width)")
        }
      }
      .onChanged { _ in exclusiveValues.append("again") }
      .onEnded { value in
        if case .second(let drag) = value { exclusiveValues.append("ended:\(drag.translation.width)") }
      }
    let erasedExclusive = _eraseGesture(exclusive)
    erasedExclusive.actionBox.changed?("tap|")
    erasedExclusive.actionBox.changed?("drag|9,0,0,0,9,0,0,0,0")
    erasedExclusive.actionBox.ended?("drag|9,0,0,0,9,0,0,0,0")
    erasedExclusive.actionBox.endedAction?()
    #expect(exclusiveValues == ["first", "again", "second:9.0", "again", "ended:9.0"])
  }

  @Test
  func gestureStateConveniencesUpdateAndRestoreMagnifyAndRotateValues() {
    let magnifyState = GestureState(wrappedValue: 1.0)
    let magnify = MagnifyGesture().updating(magnifyState) { value, current, _ in
      current = value.magnification
    }
    let erasedMagnify = _eraseGesture(magnify)
    erasedMagnify.actionBox.changed?("2.25")
    #expect(magnifyState.wrappedValue == 2.25)
    erasedMagnify.actionBox.changed?("bad")
    #expect(magnifyState.wrappedValue == 2.25)
    erasedMagnify.actionBox.reset?()
    #expect(magnifyState.wrappedValue == 1)

    var rotateState = GestureState(wrappedValue: Angle.zero)
    let rotate = RotateGesture().updating(rotateState) { value, current, _ in
      current = value.rotation
    }
    let erasedRotate = _eraseGesture(rotate)
    erasedRotate.actionBox.changed?("1.25")
    #expect(rotateState.wrappedValue == .radians(1.25))
    erasedRotate.actionBox.reset?()
    #expect(rotateState.wrappedValue == .zero)
  }
}
