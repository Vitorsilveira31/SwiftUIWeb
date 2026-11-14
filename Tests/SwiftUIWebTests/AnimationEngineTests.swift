import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// What Swift animates itself: curves evaluated in Swift, custom animations, transactions, and the `Animatable` data
/// of views, modifiers, shapes and geometry effects rendered frame by frame.
@Suite(.serialized, .processGlobalState)
@MainActor
final class AnimationEngineTests {
  private nonisolated(unsafe) static var now = 0.0

  init() {
    AnimationEngineTests.now = 100
    _animationClockOverride = { AnimationEngineTests.now }
  }

  deinit { _animationClockOverride = nil }

  // MARK: Curves

  @Test
  func timingCurvesFollowTheirBezier() {
    #expect(abs(_unitBezier(0, 0, 1, 1, at: 0.3) - 0.3) < 1e-6)
    #expect(abs(_unitBezier(0.42, 0, 0.58, 1, at: 0.5) - 0.5) < 1e-6)
    // CSS's ease-in at half time is about 0.315.
    #expect(abs(_unitBezier(0.42, 0, 1, 1, at: 0.5) - 0.3153) < 0.001)
  }

  @Test
  func theFractionHonorsDelaySpeedAndRepeats() {
    var context = AnimationContext<Double>()
    let linear = Animation.linear(duration: 1)
    #expect(linear._fraction(at: 0.5, context: &context) == 0.5)
    #expect(linear._fraction(at: 1.01, context: &context) == nil)
    #expect(linear.delay(0.5)._fraction(at: 0.5, context: &context) == 0)
    #expect(abs((linear.delay(0.5)._fraction(at: 1, context: &context) ?? -1) - 0.5) < 1e-6)
    #expect(abs((linear.speed(2)._fraction(at: 0.25, context: &context) ?? -1) - 0.5) < 1e-6)
    let twice = linear.repeatCount(2, autoreverses: true)
    print("REPEATDEBUG", twice._fraction(at: 1.25, context: &context) as Any, twice._fraction(at: 0.25, context: &context) as Any)
    #expect(abs((twice._fraction(at: 1.25, context: &context) ?? -1) - 0.75) < 1e-6)
    #expect(twice._fraction(at: 2.1, context: &context) == nil)
    // A bouncy spring passes its target on the way.
    var peak = 0.0, time = 0.0
    while let value = Animation.bouncy(duration: 0.5)._fraction(at: time, context: &context) { peak = max(peak, value); time += 0.01 }
    #expect(peak > 1.01)
  }

  @Test
  func animateScalesTheChange() {
    var context = AnimationContext<AnimatablePair<Double, Double>>()
    let value = Animation.linear(duration: 2).animate(value: AnimatablePair(10.0, -4.0), time: 1, context: &context)
    #expect(value == AnimatablePair(5.0, -2.0))
  }

  // MARK: Custom animations



  // MARK: Transactions


  // MARK: Animatable views



  private func text(_ tree: FiberTree) -> String { tree.renderNode.htmlDescription }

  @Test
  func anAnimatableViewRendersEachFrameOfItsAnimation() throws {
    let capture = Capture()
    let tree = FiberTree(MeterHost(capture: capture))
    defer { tree._dispose() }
    #expect(text(tree).contains("level 0"))
    withAnimation(.linear(duration: 1)) { capture.level?.wrappedValue = 100 }
    // The commit shows where the animation starts, and keeps a frame timeline while it moves.
    #expect(text(tree).contains("level 0"))
    #expect(text(tree).contains("data-timeline-view=\"animation\""))
    _ = try #require(capture.level)._sourceStore?._takeAnimationTransactionCSS()
    AnimationEngineTests.now += 0.25
    _ = tree._hostTimelineTick()
    #expect(text(tree).contains("level 25"))
    AnimationEngineTests.now += 1
    _ = tree._hostTimelineTick()
    #expect(text(tree).contains("level 100"))
    #expect(!text(tree).contains("data-timeline-animation-frame"))
  }

  @Test
  func aChangeWithoutAnAnimationJumps() {
    let capture = Capture()
    let tree = FiberTree(MeterHost(capture: capture))
    defer { tree._dispose() }
    capture.level?.wrappedValue = 60
    #expect(text(tree).contains("level 60"))
    #expect(!text(tree).contains("data-timeline-animation-frame"))
  }

  @Test
  func anInterruptedAnimationContinuesFromWhereItWas() throws {
    let capture = Capture()
    let tree = FiberTree(MeterHost(capture: capture))
    defer { tree._dispose() }
    withAnimation(.linear(duration: 1)) { capture.level?.wrappedValue = 100 }
    _ = try #require(capture.level)._sourceStore?._takeAnimationTransactionCSS()
    AnimationEngineTests.now += 0.5
    _ = tree._hostTimelineTick()
    #expect(text(tree).contains("level 50"))
    // Back to 0 from 50: half way there after half the new animation.
    withAnimation(.linear(duration: 1)) { capture.level?.wrappedValue = 0 }
    _ = try #require(capture.level)._sourceStore?._takeAnimationTransactionCSS()
    AnimationEngineTests.now += 0.5
    _ = tree._hostTimelineTick()
    #expect(text(tree).contains("level 25"))
  }

  // MARK: Modifiers and geometry effects



  @Test
  func aGeometryEffectDrawsItsAnimatedTransform() throws {
    let capture = Capture()
    let tree = FiberTree(ShakeHost(capture: capture))
    defer { tree._dispose() }
    #expect(!text(tree).contains("matrix3d"))
    withAnimation(.linear(duration: 1)) { capture.level?.wrappedValue = 40 }
    _ = try #require(capture.level)._sourceStore?._takeAnimationTransactionCSS()
    AnimationEngineTests.now += 0.5
    _ = tree._hostTimelineTick()
    #expect(text(tree).contains("matrix3d(1,0,0,0,0,1,0,0,0,0,1,0,20,0,0,1)"))
  }

  // A geometry effect over content the staged render defers keeps its transform while it animates, as with plain recursion.
  @Test
  func aGeometryEffectOverDeferredContentDrawsItsAnimatedTransform() throws {
    func frame(budget: Int) throws -> (html: String, moving: Bool) {
      let saved = _RenderStaging.budget
      _RenderStaging.budget = budget
      defer { _RenderStaging.budget = saved }
      let capture = Capture()
      let tree = FiberTree(DeferredShakeHost(capture: capture))
      defer { tree._dispose() }
      _ = tree.renderNode
      withAnimation(.linear(duration: 1)) { capture.level?.wrappedValue = 40 }
      _ = try #require(capture.level)._sourceStore?._takeAnimationTransactionCSS()
      AnimationEngineTests.now += 0.5
      _ = tree._hostTimelineTick()
      let html = text(tree)
      AnimationEngineTests.now -= 0.5
      return (html, html.contains("data-timeline-driven"))
    }
    let plain = try frame(budget: 0)
    #expect(plain.html.contains("matrix3d(1,0,0,0,0,1,0,0,0,0,1,0,20,0,0,1)"))
    for budget in [1, 2, 3] {
      let staged = try frame(budget: budget)
      #expect(staged.html == plain.html, "budget \(budget): the staged tree differs from the plain one")
    }
  }

  @Test
  func projectionTransformsComposeAndInvert() {
    let move = ProjectionTransform(CGAffineTransform(translationX: 10, y: 5))
    let scale = ProjectionTransform(CGAffineTransform(scaleX: 2, y: 2))
    let both = move.concatenating(scale)
    // Moved, then scaled: (0, 0) lands at (20, 10).
    #expect(both.m31 == 20 && both.m32 == 10)
    #expect(both.concatenating(both.inverted()).isIdentity)
    #expect(both.isAffine)
  }

  // MARK: Shapes



  @Test
  func anAnimatableShapeDrawsTheFramesOfItsPath() throws {
    let capture = Capture()
    let tree = FiberTree(BarHost(capture: capture))
    defer { tree._dispose() }
    withAnimation(.linear(duration: 1)) { capture.level?.wrappedValue = 1 }
    _ = try #require(capture.level)._sourceStore?._takeAnimationTransactionCSS()
    AnimationEngineTests.now += 0.5
    _ = tree._hostTimelineTick()
    // Half way, the bar is half as wide.
    #expect(text(tree).contains("data-shape-path=\"M 0 0 L 50 0 L 50 10 L 0 10 Z\""))
  }

  // MARK: .transaction and .animation(_:body:)


  @Test
  func anAnimatedTextRendererDrawsEachFrame() throws {
    let capture = Capture()
    let tree = FiberTree(FadeHost(capture: capture))
    defer { tree._dispose() }
    tree.dispatch(event: "textLayout", value: twoRuns)
    func opacity() -> Double? {
      guard let canvas = _canvas(in: tree.renderNode) else { return nil }
      for command in canvas._canvasCommands { if case .opacity(let value) = command { return value } }
      return nil
    }
    #expect(opacity() == 0)
    withAnimation(.linear(duration: 1)) { capture.level?.wrappedValue = 1 }
    _ = try #require(capture.level)._sourceStore?._takeAnimationTransactionCSS()
    AnimationEngineTests.now += 0.25
    _ = tree._hostTimelineTick()
    #expect(abs((opacity() ?? -1) - 0.25) < 0.001)
    AnimationEngineTests.now += 1
    _ = tree._hostTimelineTick()
    #expect(opacity() == 1)
  }

  @Test
  func aTransactionModifierTurnsTheAnimationOffBelowIt() {
    let capture = Capture()
    let tree = FiberTree(Disabled(capture: capture))
    defer { tree._dispose() }
    withAnimation(.linear(duration: 1)) { capture.level?.wrappedValue = 80 }
    #expect(text(tree).contains("level 80"))
    #expect(text(tree).contains("data-transaction-timing=\"none\""))
  }
}

private final class Capture { var level: Binding<Double>? }

private struct Steps: CustomAnimation {
  let duration: Double
  func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
    guard time < duration else { return nil }
    context.state[CallCount.self] += 1
    return value.scaled(by: (time / duration * 4).rounded(.down) / 4)
  }
}

private struct CallCount: AnimationStateKey { static var defaultValue: Int { 0 } }

@Test
func aCustomAnimationRunsInSwiftAndPlaysAsAnEasing() {
  let animation = Animation(Steps(duration: 1))
  var context = AnimationContext<Double>()
  #expect(animation.animate(value: 8.0, time: 0.6, context: &context) == 4)
  #expect(context.state[CallCount.self] == 1)
  #expect(animation.animate(value: 8.0, time: 1.2, context: &context) == nil)
  // The page plays it for as long as it runs, along its samples.
  #expect(abs(animation._playedDuration - 1) < 0.05)
  #expect(animation._timingFunction.hasPrefix("linear(0,0,"))
  #expect(Animation(Steps(duration: 1)) == animation)
  #expect(Animation(Steps(duration: 2)) != animation)
}

private struct Flag: TransactionKey { static var defaultValue: Bool { false } }

@Test
func transactionsCarryKeysAndCompletions() {
  var transaction = Transaction(animation: .linear(duration: 0.2))
  #expect(transaction[Flag.self] == false)
  transaction[Flag.self] = true
  #expect(transaction[Flag.self])
  var completed = 0
  transaction.addAnimationCompletion { completed += 1 }
  var seen: Bool?
  withTransaction(transaction) { seen = _AnimationTransactionRuntime.transaction?[Flag.self] }
  #expect(seen == true)
  // Without a browser scheduler a completion runs once the body has.
  #expect(completed == 1)
  withTransaction(\.disablesAnimations, true) { seen = _AnimationTransactionRuntime.transaction?.disablesAnimations }
  #expect(seen == true)
}

private struct Meter: View, Animatable {
  var level: Double
  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }
  var body: some View { Text("level \(Int(level.rounded()))") }
}

private struct MeterHost: View {
  @State var level = 0.0
  let capture: Capture
  var body: some View {
    capture.level = $level
    return Meter(level: level)
  }
}

nonisolated private struct Shake: GeometryEffect {
  var amount: Double
  var animatableData: Double {
    get { amount }
    set { amount = newValue }
  }
  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: amount, y: 0))
  }
}

private struct ShakeHost: View {
  @State var level = 0.0
  let capture: Capture
  var body: some View {
    capture.level = $level
    return Text("Shake").modifier(Shake(amount: level))
  }
}

/// `content` under `depth` stacks: deep enough for the staged render to defer it.
private struct DeferredDeep<Content: View>: View {
  let depth: Int
  let content: Content
  var body: some View {
    if depth == 0 { content } else { VStack { DeferredDeep(depth: depth - 1, content: content) } }
  }
}

private struct DeferredShakeHost: View {
  @State var level = 0.0
  let capture: Capture
  var body: some View {
    capture.level = $level
    return DeferredDeep(depth: 8, content: Text("Shake")).modifier(Shake(amount: level))
  }
}

private struct Bar: Shape {
  var fraction: Double
  var animatableData: Double {
    get { fraction }
    set { fraction = newValue }
  }
  func path(in rect: CGRect) -> Path {
    Path(CGRect(x: 0, y: 0, width: rect.width * fraction, height: rect.height))
  }
}

private struct BarHost: View {
  @State var level = 0.0
  let capture: Capture
  var body: some View {
    capture.level = $level
    return Bar(fraction: level).fill(Color.blue).frame(width: 100, height: 10)
  }
}

private struct Disabled: View {
  @State var level = 0.0
  let capture: Capture
  var body: some View {
    capture.level = $level
    return Meter(level: level).transaction { $0.animation = nil }
  }
}


/// Keyframes are evaluated in Swift: each segment's own curve, a cubic spline's velocities, a spring's motion.
@Suite
struct KeyframeCurveTests {
  @Test
  func cubicKeyframesFollowTheirVelocities() {
    let still = KeyframeTimeline(initialValue: 0.0) {
      CubicKeyframe(10.0, duration: 1)
    }
    // Without velocities a lone cubic eases in and out: half way at half time.
    #expect(abs(still.value(time: 0.5) - 5) < 1e-6)
    let launched = KeyframeTimeline(initialValue: 0.0) {
      CubicKeyframe(10.0, duration: 1, startVelocity: 30, endVelocity: 0)
    }
    // A fast start is ahead of the plain spline.
    #expect(launched.value(time: 0.25) > still.value(time: 0.25) + 1)
  }

  @Test
  func linearKeyframesApplyTheirTimingCurve() {
    let eased = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(1.0, duration: 1, timingCurve: .easeIn)
    }
    #expect(abs(eased.value(time: 0.5) - UnitCurve.easeIn.value(at: 0.5)) < 1e-6)
    #expect(UnitCurve.easeIn.value(at: 0.5) < 0.4)
  }

  @Test
  func unitCurvesEvaluateAndInvert() {
    #expect(abs(UnitCurve.linear.value(at: 0.3) - 0.3) < 1e-6)
    let curve = UnitCurve.easeInOut
    #expect(abs(curve.inverse.value(at: curve.value(at: 0.2)) - 0.2) < 1e-3)
    #expect(abs(UnitCurve.circularEaseIn.inverse.value(at: UnitCurve.circularEaseIn.value(at: 0.6)) - 0.6) < 1e-6)
    #expect(UnitCurve.easeInOut.velocity(at: 0.5) > 1)
  }

  @Test
  func springKeyframesOvershootLikeTheirSpring() {
    let bouncy = KeyframeTimeline(initialValue: 0.0) {
      SpringKeyframe(1.0, duration: 1, spring: Spring(duration: 0.5, bounce: 0.4))
    }
    var peak = 0.0, time = 0.0
    while time <= 1 { peak = max(peak, bouncy.value(time: time)); time += 0.01 }
    #expect(peak > 1.05)
    #expect(abs(bouncy.value(time: 1) - 1) < 1e-6)
  }
}

nonisolated private struct Fade: TextRenderer {
  var level: Double
  var animatableData: Double {
    get { level }
    set { level = newValue }
  }
  func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
    ctx.opacity = level
    for line in layout { ctx.draw(line) }
  }
}

private struct FadeHost: View {
  @State var level = 0.0
  let capture: Capture
  var body: some View {
    capture.level = $level
    return Text("abc").textRenderer(Fade(level: level))
  }
}
