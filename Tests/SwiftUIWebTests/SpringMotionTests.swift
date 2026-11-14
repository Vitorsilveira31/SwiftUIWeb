import Testing
import SwiftUIWeb
@testable import SwiftUIWebCore

/// The springs follow the damped oscillator SwiftUI's `Spring` describes, and the browser plays them along that curve.
@Suite
struct SpringMotionTests {
  private func peak(_ motion: _SpringMotion) -> Double {
    var best = 0.0, time = 0.0
    while time < 3 { best = max(best, motion.value(at: time)); time += 0.001 }
    return best
  }

  @Test
  func criticallyDampedSpringNeverOvershootsAndSettles() {
    let motion = _SpringMotion(duration: 0.5, bounce: 0)
    #expect(peak(motion) <= 1.0005)
    let settle = motion.settlingDuration()
    // ω = 2π / 0.5; (1 + ωt)e^{-ωt} falls under 1e-3 at ωt ≈ 9.23, about 0.73 s.
    #expect(settle > 0.65 && settle < 0.8)
    #expect(abs(motion.value(at: settle) - 1) <= 0.0015)
  }

  @Test
  func bounceSetsTheOvershootLikeSwiftUI() {
    // Bounce b is damping ratio 1 - b; the first overshoot of an underdamped step is exp(-ζπ/√(1-ζ²)).
    for bounce in [0.15, 0.3, 0.5] {
      let zeta = 1 - bounce
      let expected = 1 + _exponential(-zeta * Double.pi / (1 - zeta * zeta).squareRoot())
      #expect(abs(peak(_SpringMotion(duration: 0.5, bounce: bounce)) - expected) < 0.005)
    }
    // A negative bounce is overdamped: 1 / (1 + b).
    #expect(_SpringMotion(duration: 0.5, bounce: -0.5).dampingRatio == 2)
    #expect(peak(_SpringMotion(duration: 0.5, bounce: -0.5)) <= 1.0005)
  }

  @Test
  func physicalSpringMatchesTheResponseSpelling() {
    // stiffness = (2π / response)² · mass, damping = 4π · ζ · mass / response.
    let response = 0.4, zeta = 0.7
    let stiffness = (2 * Double.pi / response) * (2 * Double.pi / response)
    let damping = 4 * Double.pi * zeta / response
    let physical = _SpringMotion(mass: 1, stiffness: stiffness, damping: damping)
    #expect(abs(physical.response - response) < 1e-9)
    #expect(abs(physical.dampingRatio - zeta) < 1e-9)
  }

  @Test
  func initialVelocityPushesTheStartOfTheCurve() {
    let still = _SpringMotion(duration: 0.5, bounce: 0), pushed = _SpringMotion(duration: 0.5, bounce: 0, initialVelocity: 8)
    #expect(pushed.value(at: 0.05) > still.value(at: 0.05))
  }

  @Test
  func cssEasingIsLinearWithSamplesEndingAtTheTarget() {
    let easing = _SpringMotion(duration: 0.5, bounce: 0.3).cssEasing(duration: 1)
    #expect(easing.hasPrefix("linear(0,"))
    #expect(easing.hasSuffix(",1)"))
    let samples = easing.dropFirst("linear(".count).dropLast().split(separator: ",").compactMap { Double(String($0)) }
    #expect(samples.count == 61)
    #expect(samples.contains { $0 > 1 })
    #expect(_easingNumber(1.0326) == "1.033")
    #expect(_easingNumber(-0.01) == "-0.01")
    #expect(_easingNumber(0.0004) == "0")
    #expect(_easingNumber(0.05) == "0.05")
  }

  @Test
  func animationsUseSwiftUIsCurvesAndDurations() {
    // Timing curves without a duration last 0.35 s.
    #expect(Animation.easeInOut.cssValue.hasPrefix("all 350ms ease-in-out"))
    #expect(Animation.linear.cssValue.hasPrefix("all 350ms linear"))
    // The default animation and every spring play their own curve until they settle.
    for animation in [Animation.default, .spring(), .smooth, .snappy, .bouncy, .interactiveSpring(), .interpolatingSpring(stiffness: 170, damping: 15)] {
      #expect(animation.cssValue.contains(" linear(0,"))
    }
    #expect(Animation.bouncy._timingFunction.split(separator: ",").contains { (Double(String($0)) ?? 0) > 1 })
    #expect(!Animation.smooth._timingFunction.split(separator: ",").contains { (Double(String($0)) ?? 0) > 1.0005 })
    // `.speed` shortens the delay that is already there, not one added after it.
    #expect(Animation.easeIn(duration: 1).delay(1).speed(2).cssValue.hasPrefix("all 500ms ease-in 500ms"))
    #expect(Animation.easeIn(duration: 1).speed(2).delay(1).cssValue.hasPrefix("all 500ms ease-in 1000ms"))
    #expect(Spring.snappy.bounce == 0.15 && Spring.bouncy.bounce == 0.3 && Spring.bouncy.duration == 0.5)
  }

  @Test
  func unlabeledSpringIsTheDurationBounceSpringAsInSwiftUI() {
    // SwiftUI disfavors the response/damping spelling: `.spring()` and `.spring` are `spring(duration: 0.5, bounce: 0)`,
    // which does not overshoot. Only the labelled response/damping spring keeps its 0.825 damping fraction.
    let critical = Animation.spring(duration: 0.5, bounce: 0)
    #expect(Animation.spring() == critical)
    #expect(Animation.spring == critical)
    #expect(Animation.spring(blendDuration: 0.1) == Animation.spring(duration: 0.5, bounce: 0, blendDuration: 0.1))
    #expect(!Animation.spring._timingFunction.split(separator: ",").contains { (Double(String($0)) ?? 0) > 1.0005 })
    #expect(Animation.spring(response: 0.5)._timingFunction.split(separator: ",").contains { (Double(String($0)) ?? 0) > 1 })
    // `.interactiveSpring()` is the duration/bounce spring too: 0.15 s with a bounce of 0.15.
    #expect(Animation.interactiveSpring() == Animation.spring(duration: 0.15, bounce: 0.15, blendDuration: 0.25))
    #expect(Animation.interactiveSpring == Animation.interactiveSpring())
    #expect(Animation.interpolatingSpring == Animation.interpolatingSpring(duration: 0.5, bounce: 0))
  }

  @Test
  func completionWaitsForTheCriteria() {
    // A timing curve is complete when it ends, its delay and repeats included.
    #expect(Animation.easeIn(duration: 1).delay(0.5)._completionDelay(.logicallyComplete) == 1.5)
    #expect(Animation.linear(duration: 0.5).repeatCount(3)._completionDelay(.removed) == 1.5)
    #expect(Animation.linear.repeatForever()._completionDelay(.removed) == nil)
    // A spring is logically complete after its response, and removed once it settles.
    let spring = Animation.spring(duration: 0.5, bounce: 0.3)
    let logical = spring._completionDelay(.logicallyComplete) ?? 0, removed = spring._completionDelay(.removed) ?? 0
    #expect(abs(logical - 0.5) < 1e-9)
    #expect(removed > logical)
  }

  @Test @MainActor
  func completionRunsAtOnceWithoutAHostTimer() {
    var completed = 0
    let value = withAnimation(.easeIn, { 42 }, completion: { completed += 1 })
    #expect(value == 42 && completed == 1)
    withAnimation(nil, { () }, completion: { completed += 1 })
    #expect(completed == 2)
  }
}
