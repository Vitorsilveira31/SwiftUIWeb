import Testing
import Foundation
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
final class AdvancedAnimationTests {
  private struct MotionValue {
    var scale: Double = 1
    var offset: Double = 0
    var angle: Angle = .zero
  }

  private struct NumericMotionValue {
    var double: Double = 0
    var float: Float = 0
    var cgFloat: CGFloat = 0
    var int: Int = 0
    var int8: Int8 = 0
    var int16: Int16 = 0
    var int32: Int32 = 0
    var int64: Int64 = 0
    var uint: UInt = 0
  }

  @Test
  func testPhaseAnimatorRendersInitialPhaseAndSemanticFrames() {
    let view = Text("Pulse")
      .phaseAnimator([false, true]) { (content: PlaceholderContentView<Text>, phase: Bool) in
        content.scaleEffect(phase ? 1.2 : 1.0)
      }

    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("data-phase-animator=\"true\""))
    _expectTrue(html.contains("data-phase-repeating=\"true\""))
    _expectTrue(html.contains("data-phase-count=\"2\""))
    _expectTrue(html.contains("data-phase-frames=\""))
    // Static/WASI hosts show the first phase, while browser hosts consume the
    // same frame metadata through WAAPI.
    _expectTrue(html.contains("scale(1.0)"))
  }

  @Test
  func testTriggeredPhaseAnimatorCarriesTriggerWithoutChangingIdentity() {
    let first = Text("Stateful")
      .phaseAnimator([0, 1, 2], trigger: 4) { content, phase in
        content.offset(x: Double(phase))
      }
    let second = Text("Stateful")
      .phaseAnimator([0, 1, 2], trigger: 5) { content, phase in
        content.offset(x: Double(phase))
      }

    let firstHTML = StaticHTMLFiberRenderer().render(first)
    let secondHTML = StaticHTMLFiberRenderer().render(second)
    _expectTrue(firstHTML.contains("data-phase-repeating=\"false\""))
    // The trigger is published as a generation of its value, not as its description (see the test of struct triggers).
    _expectTrue(firstHTML.contains("data-phase-trigger=\"") && !firstHTML.contains("data-phase-trigger=\"\""))
    _expectTrue(secondHTML.contains("data-phase-trigger=\"") && !secondHTML.contains("data-phase-trigger=\"\""))
    _expectTrue(firstHTML.contains("data-phase-count=\"3\""))
    _expectTrue(secondHTML.contains("data-phase-count=\"3\""))
  }

  @Test
  func testEmptyPhaseSequenceIsRepresentedSafely() {
    let html = StaticHTMLFiberRenderer().render(
      PhaseAnimator([Int]()) { phase in Text("\(phase)") }
    )
    _expectTrue(html.contains("data-phase-animator-error=\"empty\""))

    let modified = Text("No phase")
      .phaseAnimator([Int]()) { (content: PlaceholderContentView<Text>, _: Int) in
        content
      }
    #expect(StaticHTMLFiberRenderer().render(modified).contains("data-phase-animator-error=\"empty\""))
  }

  @Test
  func testPhaseAnimatorContainerTriggerInitializer() {
    let view = PhaseAnimator([0, 1, 2], trigger: 3) { phase in
      Text("Phase \(phase)").offset(x: Double(phase))
    }
    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("data-phase-repeating=\"false\""))
    _expectTrue(html.contains("data-phase-trigger=\"") && !html.contains("data-phase-trigger=\"\""))
  }

  @Test
  func testKeyframeTimelineInterpolatesWritableTracks() {
    let timeline = KeyframeTimeline(initialValue: MotionValue()) {
      KeyframeTrack(\.scale) {
        LinearKeyframe(2.0, duration: 1.0)
        CubicKeyframe(1.0, duration: 1.0)
      }
      KeyframeTrack(\.offset) {
        MoveKeyframe(12.0)
      }
      KeyframeTrack(\.angle) {
        LinearKeyframe(Angle.degrees(90), duration: 0.2)
      }
    }

    _expectEqual(timeline.duration, 2.0, accuracy: 0.0001)
    _expectEqual(timeline.value(progress: 0).scale, 1.0, accuracy: 0.0001)
    _expectEqual(timeline.value(progress: 0.25).scale, 1.5, accuracy: 0.0001)
    _expectEqual(timeline.value(progress: 1).scale, 1.0, accuracy: 0.0001)
    _expectEqual(timeline.value(progress: 0.1).offset, 12.0, accuracy: 0.0001)
    _expectEqual(timeline.value(progress: 1).angle.radians, .pi / 2, accuracy: 0.0001)
    _ = SpringKeyframe(1.0, spring: .bouncy)
  }

  @Test
  func testSpringAndCurveInitializersPreserveTheirSemanticValues() {
    let bezier = UnitCurve.cubicBezier(0.1, 0.2, 0.8, 0.9)
    #expect(bezier.rawValue == "cubic-bezier(0.1,0.2,0.8,0.9)")
    #expect(UnitCurve(rawValue: "steps(2)").rawValue == "steps(2)")

    let overdamped = Spring(mass: 1, stiffness: 100, damping: 40, allowOverDamping: true)
    #expect(overdamped.duration > 0)
    #expect(overdamped.bounce < 0)

    let underdamped = Spring(mass: 1, stiffness: 100, damping: 2)
    #expect(underdamped.bounce > 0)
    #expect(Spring(mass: -1, stiffness: 0, damping: -1).duration >= 0.12)

    // A damping ratio above one is overdamped by that ratio: the bounce is the one the motion reads back as the same ratio.
    let response = Spring(response: -2, dampingRatio: 2)
    #expect(response.duration == 0.01)
    #expect(response.bounce == -0.5)
    #expect(abs(_SpringMotion(duration: 0.5, bounce: response.bounce).dampingRatio - 2) < 1e-9)
    #expect(abs(_SpringMotion(duration: 0.5, bounce: Spring(response: 0.5, dampingRatio: 1.5).bounce).dampingRatio - 1.5) < 1e-9)
    #expect(Spring(response: 0.5, dampingRatio: 0.7).bounce == 1 - 0.7)
    #expect(Spring(response: 0.5, dampingRatio: .infinity).bounce == -1)
    // Without allowOverDamping an overdamped spring is critically damped; an underdamped one bounces either way.
    #expect(Spring(mass: 1, stiffness: 100, damping: 40).bounce == 0)
    #expect(Spring(mass: 1, stiffness: 100, damping: 2, allowOverDamping: true).bounce > 0)
    #expect(Spring(settlingDuration: 1, dampingRatio: 4).bounce == -0.75)
    let settling = Spring(settlingDuration: -2, dampingRatio: -1, epsilon: 0.1)
    #expect(settling.duration == 0)
    #expect(settling.bounce == 1)

    let cubic = CubicKeyframe(4.0, duration: 0.4, startVelocity: 0.25, endVelocity: 0.75)
    #expect(cubic.startVelocity == 0.25)
    #expect(cubic.endVelocity == 0.75)
    #expect(cubic._swiftUIWebKeyframeSegments.first?.kind == .cubic)
  }

  @Test
  func testTimelineTimeSamplingAndEmptyTracksKeepTheInitialValue() {
    let timeline = KeyframeTimeline(initialValue: MotionValue()) {
      KeyframeTrack(\.scale) {
        LinearKeyframe(3.0, duration: 2)
      }
    }

    #expect(timeline.value(time: 1).scale == 2)
    #expect(timeline.value(time: 10).scale == 3)

    let emptyTrack = KeyframeTrack<Double, Double, _KeyframeSegments<Double>> { _KeyframeSegments<Double>([]) }
    #expect(emptyTrack.content._swiftUIWebKeyframeSegments.isEmpty)
    let emptyTrackTimeline = KeyframeTimeline(
      initialValue: 7.0,
      tracks: emptyTrack._swiftUIWebKeyframeTracks(initialValue: 7.0)
    )
    #expect(emptyTrackTimeline.value(progress: 0.5) == 7)
    let emptyTimeline = KeyframeTimeline(initialValue: 7.0, tracks: [])
    #expect(emptyTimeline.duration == 0)
    #expect(emptyTimeline.value(time: 0) == 7)
    #expect(emptyTimeline.value(progress: -1) == 7)
  }

  @Test
  func testNumericKeyframeTracksInterpolateEverySupportedScalarType() {
    let timeline = KeyframeTimeline(initialValue: NumericMotionValue()) {
      KeyframeTrack(\.double) { LinearKeyframe(3.0, duration: 1) }
      KeyframeTrack(\.float) { LinearKeyframe(Float(3), duration: 1) }
      KeyframeTrack(\.cgFloat) { LinearKeyframe(CGFloat(3), duration: 1) }
      KeyframeTrack(\.int) { LinearKeyframe(3, duration: 1) }
      KeyframeTrack(\.int8) { LinearKeyframe(Int8(3), duration: 1) }
      KeyframeTrack(\.int16) { LinearKeyframe(Int16(3), duration: 1) }
      KeyframeTrack(\.int32) { LinearKeyframe(Int32(3), duration: 1) }
      KeyframeTrack(\.int64) { LinearKeyframe(Int64(3), duration: 1) }
      KeyframeTrack(\.uint) { LinearKeyframe(UInt(3), duration: 1) }
    }

    let midpoint = timeline.value(time: 0.5)
    #expect(midpoint.double == 1.5)
    #expect(midpoint.float == 1.5)
    #expect(midpoint.cgFloat == 1.5)
    #expect(midpoint.int == 2)
    #expect(midpoint.int8 == 2)
    #expect(midpoint.int16 == 2)
    #expect(midpoint.int32 == 2)
    #expect(midpoint.int64 == 2)
    #expect(midpoint.uint == 2)

    var largeInitial = NumericMotionValue()
    largeInitial.int64 = .max
    let largeInteger = KeyframeTimeline(initialValue: largeInitial) {
      KeyframeTrack(\.int64) { LinearKeyframe(Int64.max, duration: 1) }
    }
    #expect(largeInteger.value(progress: 0.5).int64 == .max)

    struct TextValue {
      var label = "idle"
    }
    let discrete = KeyframeTimeline(initialValue: TextValue()) {
      KeyframeTrack(\.label) { LinearKeyframe("finished", duration: 1) }
    }
    #expect(discrete.value(progress: 0.25).label == "idle")
    #expect(discrete.value(progress: 0.75).label == "idle")
    #expect(discrete.value(progress: 1).label == "finished")
  }

  @Test
  func testKeyframeBuildersHandleBranchesOptionalLoopsAndCustomTracks() {
    struct SingleValue {
      var value = 0.0
    }
    func makeTrack(chooseFirst: Bool) -> KeyframeTimeline<Double> {
      KeyframeTimeline<Double>(initialValue: 0.0) {
        KeyframeTrack {
          if chooseFirst {
            LinearKeyframe(1.0, duration: 0.2)
          } else {
            CubicKeyframe(1.0, duration: 0.2)
          }
        }
      }
    }
    let firstTrack = makeTrack(chooseFirst: true)
    let secondTrack = makeTrack(chooseFirst: false)
    #expect(firstTrack.tracks.flatMap(\.segments).map(\.kind) == [.linear])
    #expect(secondTrack.tracks.flatMap(\.segments).map(\.kind) == [.cubic])

    let loopTrack = KeyframeTimeline<Double>(initialValue: 0.0) {
      KeyframeTrack {
        for value in [3.0, 4.0] {
          LinearKeyframe(value, duration: 0.1)
        }
      }
    }
    #expect(loopTrack.tracks.flatMap(\.segments).count == 2)

    let explicitSegments = LinearKeyframe(5.0, duration: 0.3)._swiftUIWebKeyframeSegments
    let arrayTrack = KeyframeTimeline<Double>(initialValue: 0.0) {
      KeyframeTrack { _KeyframeSegments<Double>(explicitSegments) }
    }
    #expect(arrayTrack.tracks.first?.segments.first?.valueDescription == "5.0")

    struct CustomTracks: Keyframes {
      typealias Value = Double
      typealias Body = Never
      func _swiftUIWebKeyframeTracks(initialValue: Double?) -> [KeyframeTrackDescriptor] {
        [KeyframeTrackDescriptor(keyPath: "custom", segments: [])]
      }
    }
    let custom = KeyframeTimeline<Double>(initialValue: 0.0) { CustomTracks() }
    #expect(custom.tracks.first?.keyPath == "custom")

    let explicitDescriptors = CustomTracks()._swiftUIWebKeyframeTracks(initialValue: 1.0)
    let descriptorArray = KeyframeTimeline<Double>(initialValue: 1.0, tracks: explicitDescriptors)
    #expect(descriptorArray.tracks.first?.keyPath == "custom")

    func makeTimeline(chooseCubic: Bool) -> KeyframeTimeline<SingleValue> {
      KeyframeTimeline(initialValue: SingleValue()) {
        KeyframeTrack(\.value) {
          if chooseCubic {
            CubicKeyframe(1.0, duration: 0.2)
          } else {
            LinearKeyframe(1.0, duration: 0.2)
          }
        }
        KeyframeTrack(\.value) {
          MoveKeyframe(2.0)
        }
        KeyframeTrack(\.value) {
          LinearKeyframe(3.0, duration: 0.1)
        }
        KeyframeTrack(\.value) {
          LinearKeyframe(4.0, duration: 0.1)
        }
      }
    }
    let source = makeTimeline(chooseCubic: false)
    let alternative = makeTimeline(chooseCubic: true)
    #expect(source.tracks.count == 4)
    #expect(source.duration == 0.2)
    #expect(alternative.tracks.count == 4)
    #expect(alternative.tracks[0].segments.first?.kind == .cubic)
  }

  @Test
  func testLaterKeyframeSegmentsSelectTheirOwnEasingAndEscapeMetadata() {
    let view = Text("Easing")
      .keyframeAnimator(initialValue: 0.0, repeating: false) { content, value in
        content.opacity(value)
      } keyframes: { _ in
        KeyframeTrack(\.self) {
          LinearKeyframe(1.0, duration: 0.1, timingCurve: UnitCurve("first"))
          LinearKeyframe(2.0, duration: 0.1, timingCurve: UnitCurve("second|semi;equals=percent%"))
          LinearKeyframe(3.0, duration: 0.1, timingCurve: UnitCurve("third"))
        }
      }

    let html = StaticHTMLFiberRenderer().render(view)
    // Swift evaluates each segment's curve and samples the timeline 60 times a second, so the page joins the samples
    // linearly; the curves stay in the track metadata, escaped.
    #expect(html.contains("data-keyframe-easings=\"linear,linear,"))
    #expect(!html.contains("data-keyframe-easings=\"first"))
    #expect(html.contains("second%7Csemi%3Bequals%3Dpercent%25"))
  }

  @Test
  func testPhaseAnimatorAllowsPerPhaseNilAndCustomAnimation() {
    let view = PhaseAnimator([0, 1]) { phase in
      Text("Phase \(phase)")
    } animation: { phase in
      phase == 0 ? .linear(duration: 0.25) : nil
    }

    let html = StaticHTMLFiberRenderer().render(view)
    #expect(html.contains("data-phase-durations=\"0.25,0\""))
    #expect(html.contains("data-phase-easing=\"linear,none\""))
  }

  @Test
  func testKeyframeAnimatorWithTriggerAndNoTracksHasStableFallbackMetadata() {
    let empty = KeyframeAnimator(initialValue: 3.0, trigger: "refresh") { value in
      Text("\(value)")
    } keyframes: { _ in }

    let html = StaticHTMLFiberRenderer().render(empty)
    #expect(html.contains("data-keyframe-trigger=\"") && !html.contains("data-keyframe-trigger=\"\""))
    #expect(html.contains("data-keyframe-duration=\"0\""))
    #expect(html.contains("data-keyframe-offsets=\"0,1\""))
    #expect(html.contains("data-keyframe-easings=\"linear\""))
  }

  @Test
  func testKeyframeAnimatorSerializesTracksAndFrames() {
    let view = Text("Keyframes")
      .keyframeAnimator(initialValue: MotionValue(), trigger: 1) { content, value in
        content
          .scaleEffect(value.scale)
          .offset(x: value.offset)
      } keyframes: { _ in
        KeyframeTrack(\.scale) {
          LinearKeyframe(1.5, duration: 0.2)
          SpringKeyframe(1.0, duration: 0.3)
        }
        KeyframeTrack(\.offset) {
          MoveKeyframe(20.0)
        }
      }

    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("data-keyframe-animator=\"true\""))
    _expectTrue(html.contains("data-keyframe-trigger=\"") && !html.contains("data-keyframe-trigger=\"\""))
    _expectTrue(html.contains("data-keyframe-duration=\"0.5\""))
    _expectTrue(html.contains("data-keyframe-offsets=\""))
    _expectTrue(html.contains("data-keyframe-easings=\""))
    _expectTrue(html.contains("data-keyframe-tracks=\""))
    _expectTrue(html.contains("data-keyframe-frames=\""))
    _expectTrue(html.contains("transform:"))
  }

  @Test
  func testKeyframeAnimatorContainerUsesSingleValueContentClosure() {
    let view = KeyframeAnimator(initialValue: 1.0, repeating: true) { value in
      Text("\(value)").opacity(value)
    } keyframes: { _ in
      KeyframeTrack(\.self) {
        LinearKeyframe(0.5, duration: 0.1)
        LinearKeyframe(1.0, duration: 0.1)
      }
    }
    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("data-keyframe-animator=\"true\""))
    _expectTrue(html.contains("data-keyframe-repeating=\"true\""))
    _expectTrue(html.contains("data-keyframe-duration=\"0.2\""))
  }

  @Test
  func testRepeatingKeyframeAnimatorMarksBrowserLoop() {
    let view = Rectangle()
      .keyframeAnimator(initialValue: 0.0, repeating: true) { content, value in
        content.opacity(value)
      } keyframes: { _ in
        KeyframeTrack(\.self) {
          LinearKeyframe(1.0, duration: 0.15)
          LinearKeyframe(0.0, duration: 0.15)
        }
      }

    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("data-keyframe-repeating=\"true\""))
    _expectTrue(html.contains("data-keyframe-duration=\"0.3\""))
  }

  @Test
  func testAnimationMetadataRenderingPerformance() {
    let view = VStack {
      ForEach(0..<60) { index in
        Text("Row \(index)")
          .phaseAnimator([false, true]) { content, phase in
            content.opacity(phase ? 0.7 : 1.0)
          }
      }
    }
    let renderer = StaticHTMLFiberRenderer()
    _measure {
      _ = renderer.render(view)
    }
  }
}
