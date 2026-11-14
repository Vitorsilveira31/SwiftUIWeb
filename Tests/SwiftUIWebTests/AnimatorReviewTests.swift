import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@testable @_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// Review findings on the Swift animator: `.animation(_:value:)` drives Swift-animated data without `withAnimation`,
/// repeats of custom animations, and custom animations evaluated for the actual change.
@Suite(.serialized, .processGlobalState)
@MainActor
final class AnimatorReviewTests {
  private nonisolated(unsafe) static var now = 0.0

  init() {
    AnimatorReviewTests.now = 100
    _animationClockOverride = { AnimatorReviewTests.now }
  }

  deinit { _animationClockOverride = nil }

  private func text(_ tree: FiberTree) -> String { tree.renderNode.htmlDescription }

  // A value-scoped animation moves Animatable data in the commit where its value changed, without `withAnimation`.
  @Test
  func valueScopedAnimationInterpolatesWithoutWithAnimation() {
    let capture = ReviewCapture()
    let tree = FiberTree(ReviewValueHost(capture: capture))
    defer { tree._dispose() }
    #expect(text(tree).contains("level 0"))
    // The value changes in a plain commit: SwiftUI animates it because `.animation(_:value:)` names the change.
    capture.level?.wrappedValue = 100
    #expect(text(tree).contains("level 0"))
    #expect(text(tree).contains("data-timeline-view=\"animation\""))
    AnimatorReviewTests.now += 0.5
    _ = tree._hostTimelineTick()
    #expect(text(tree).contains("level 50"))
    AnimatorReviewTests.now += 1
    _ = tree._hostTimelineTick()
    #expect(text(tree).contains("level 100"))
  }

  // A custom animation repeated with `repeatCount` runs for every iteration, not just its first.
  @Test
  func repeatedCustomAnimationRunsForEveryIteration() {
    let animation = Animation(ReviewRamp()).repeatCount(2, autoreverses: false)
    var context = AnimationContext<Double>()
    // Half a second into the second iteration the ramp is about half way.
    let middle = animation._fraction(at: 0.75, context: &context)
    #expect(middle != nil)
    #expect(abs((middle ?? -1) - 0.47) < 0.05)
    // Two iterations of about half a second each: the run is over after them.
    #expect(animation._fraction(at: 1.6, context: &context) == nil)
  }

  // A custom animation sees the actual change: one unit per second over a change of 10 is 0.5 after 0.5 seconds.
  @Test
  func customAnimationEvaluatesTheActualChange() {
    let animation = Animation(ReviewOneUnitPerSecond())
    var context = AnimationContext<Double>()
    let value = animation.animate(value: 10.0, time: 0.5, context: &context)
    #expect(abs((value ?? -1) - 0.5) < 0.001)
  }

  // A custom animation's own velocity is the animation's velocity: scaled by its speed, zero before its delay, and nil
  // when the custom animation has none.
  @Test
  func customAnimationReportsItsOwnVelocity() {
    let context = AnimationContext<Double>()
    #expect(Animation(ReviewFixedVelocity()).velocity(value: 4.0, time: 0.5, context: context) == 20)
    #expect(Animation(ReviewFixedVelocity()).speed(2).velocity(value: 4.0, time: 0.5, context: context) == 40)
    #expect(Animation(ReviewFixedVelocity()).delay(1).velocity(value: 4.0, time: 0.5, context: context) == 0)
    #expect(Animation(ReviewRamp()).velocity(value: 4.0, time: 0.25, context: context) == nil)
    #expect(Animation.linear(duration: 1).velocity(value: 4.0, time: 0.5, context: context) != nil)
  }

  // A custom animation driving Swift animatable data reads the environment of the view it animates.
  @Test
  func customAnimationRunsInTheViewsEnvironment() {
    let capture = ReviewCapture()
    let tree = FiberTree(ReviewEnvironmentHost(capture: capture).environment(\.reviewProbe, true))
    defer { tree._dispose() }
    capture.level?.wrappedValue = 10
    AnimatorReviewTests.now += 0.25
    _ = tree._hostTimelineTick()
    #expect(ReviewEnvironmentProbe.seen.contains(true))
  }

  // `.animation(nil, value:)` turns off the animation an ancestor's `withAnimation` asked for, when its value changes.
  @Test
  func nilValueScopedAnimationOptsOutOfWithAnimation() {
    let capture = ReviewCapture()
    let tree = FiberTree(ReviewOptOutHost(capture: capture))
    defer { tree._dispose() }
    #expect(text(tree).contains("level 0"))
    withAnimation(.linear(duration: 1)) { capture.level?.wrappedValue = 100 }
    #expect(text(tree).contains("level 100"))
    #expect(!text(tree).contains("data-timeline-view=\"animation\""))
  }

  // `.animation(_:body:)` animates what the closure's modifiers change, not the data of the view it modifies.
  @Test
  func scopedAnimationLeavesThePlaceholderViewsDataAlone() {
    let capture = ReviewCapture()
    let tree = FiberTree(ReviewScopedHost(capture: capture))
    defer { tree._dispose() }
    #expect(text(tree).contains("level 0"))
    capture.level?.wrappedValue = 100
    #expect(text(tree).contains("level 100"))
    #expect(!text(tree).contains("data-timeline-view=\"animation\""))
  }

  // A speculative render shows the target and leaves the animator's state as it was.
  @Test
  func speculativeRenderDoesNotTouchTheAnimatorState() {
    var context = _RenderContext()
    context._speculative = true
    let shown = _Animator.present(10.0, key: "speculative#data", context: context)
    #expect(shown.value == 10 && !shown.moving)
    #expect(context.stateStore._animatorValues.isEmpty)

    context._speculative = false
    _ = _Animator.present(1.0, key: "real#data", context: context)
    #expect(!context.stateStore._animatorValues.isEmpty)
    context._speculative = true
    #expect(_Animator.present(50.0, key: "real#data", context: context).value == 50)
    context._speculative = false
    // The real render still finds the value it showed before, not the speculative target.
    #expect(_Animator.present(1.0, key: "real#data", context: context).value == 1)
  }

  // A speculative render shows the value the animation under way has reached, as the real render does, and writes nothing.
  @Test
  func speculativeRenderReadsTheInFlightValueFromACopy() {
    var context = _RenderContext()
    _ = _Animator.present(0.0, key: "flight#data", context: context)
    var transaction = Transaction()
    transaction.animation = .linear(duration: 1)
    context._transactionOverride = transaction
    _ = _Animator.present(100.0, key: "flight#data", context: context)
    AnimatorReviewTests.now += 0.5
    context._transactionOverride = nil
    let real = _Animator.present(100.0, key: "flight#data", context: context)
    #expect(abs(real.value - 50) < 1 && real.moving)
    AnimatorReviewTests.now += 0.25
    context._speculative = true
    let speculative = _Animator.present(100.0, key: "flight#data", context: context)
    #expect(abs(speculative.value - 75) < 1 && speculative.moving)
    // A speculative render of another target (the flip changes the data) shows that target.
    #expect(_Animator.present(7.0, key: "flight#data", context: context).value == 7)
    // Nothing was written: the real render goes on from 75.
    context._speculative = false
    #expect(abs(_Animator.present(100.0, key: "flight#data", context: context).value - 75) < 1)
  }

  // The placeholder view of a scoped transaction does not inherit the flag the scoped transform set.
  @Test
  func placeholderDoesNotInheritTheScopedClearedFlag() {
    var context = _RenderContext()
    context._animationCleared = true
    context._placeholderTransaction = _PlaceholderTransaction(override: nil, cleared: false)
    let node = PlaceholderContentView<Text>(AnyView(Text("x").transaction { _ in }))._render(in: context)
    #expect(node.attributes["data-transaction-timing"] == nil)
    context._placeholderTransaction = _PlaceholderTransaction(override: nil, cleared: true)
    let cleared = PlaceholderContentView<Text>(AnyView(Text("x").transaction { _ in }))._render(in: context)
    #expect(cleared.attributes["data-transaction-timing"] == "none")
  }

  // A value-scoped animation closest to the data wins over the `withAnimation` above it.
  @Test
  func valueScopedAnimationOverridesAnInheritedOne() {
    let capture = ReviewCapture()
    let tree = FiberTree(ReviewValueHost(capture: capture))
    defer { tree._dispose() }
    withAnimation(.linear(duration: 10)) { capture.level?.wrappedValue = 100 }
    AnimatorReviewTests.now += 1.5
    _ = tree._hostTimelineTick()
    // Its own one second, not the ten of the commit.
    #expect(text(tree).contains("level 100"))
  }

  // Two value-scoped animations on one view each keep the history of their own value, whatever its type.
  @Test
  func stackedValueAnimationsKeepTheirOwnHistories() {
    let capture = ReviewCapture()
    let tree = FiberTree(ReviewStackedHost(capture: capture))
    defer { tree._dispose() }
    capture.level?.wrappedValue = 100
    #expect(text(tree).contains("level 0"))
    AnimatorReviewTests.now += 0.5
    _ = tree._hostTimelineTick()
    #expect(text(tree).contains("level 50"))
    AnimatorReviewTests.now += 1
    _ = tree._hostTimelineTick()
    #expect(text(tree).contains("level 100"))
  }

  // The trigger of a scroll indicator flash is any Equatable value: one without a description (a struct) triggers when it
  // stops being equal, and only then.
  @Test
  func aScrollFlashTriggersOnAnyEquatableValue() {
    let capture = ReviewFlashCapture()
    let tree = FiberTree(ReviewFlashHost(capture: capture))
    defer { tree._dispose() }
    func token() -> String? {
      let html = text(tree)
      guard let start = html.range(of: "data-scroll-flash=\"") else { return nil }
      return String(html[start.upperBound...].prefix { $0 != "\"" })
    }
    let first = token()
    #expect(first != nil)
    capture.unrelated?.wrappedValue += 1
    #expect(token() == first)
    capture.trigger?.wrappedValue = ReviewFlashTrigger(page: 2, section: "a")
    let second = token()
    #expect(second != nil && second != first)
    capture.trigger?.wrappedValue = ReviewFlashTrigger(page: 2, section: "a")
    #expect(token() == second)
    capture.trigger?.wrappedValue = ReviewFlashTrigger(page: 2, section: "b")
    #expect(token() != second)
  }

  // The trigger of a phase or keyframe animator is any Equatable value: a struct, which has no description in Embedded
  // Swift, restarts the animator when it stops being equal, and only then.
  @Test
  func animatorsTriggerOnAnyEquatableValue() {
    let capture = ReviewFlashCapture()
    let tree = FiberTree(ReviewAnimatorHost(capture: capture))
    defer { tree._dispose() }
    func tokens() -> [String] {
      ["data-phase-trigger=\"", "data-keyframe-trigger=\""].map { name in
        let html = text(tree)
        var found: [String] = []
        var rest = Substring(html)
        while let start = rest.range(of: name) {
          let value = rest[start.upperBound...].prefix { $0 != "\"" }
          found.append(String(value))
          rest = rest[start.upperBound...]
        }
        return found.joined(separator: ",")
      }
    }
    let first = tokens()
    #expect(first.allSatisfy { !$0.isEmpty && !$0.contains(",,") })
    capture.unrelated?.wrappedValue += 1
    #expect(tokens() == first)
    capture.trigger?.wrappedValue = ReviewFlashTrigger(page: 2, section: "a")
    let second = tokens()
    #expect(second[0] != first[0] && second[1] != first[1])
    capture.trigger?.wrappedValue = ReviewFlashTrigger(page: 2, section: "a")
    #expect(tokens() == second)
  }

  // The samples a keyframe animator renders and discards do not advance the history of what the mounted one contains: a
  // child animator triggered by the sampled value keeps its trigger across unrelated renders.
  @Test
  func discardedKeyframeSamplesDoNotAdvanceAChildsTrigger() {
    let capture = ReviewFlashCapture()
    let tree = FiberTree(ReviewNestedAnimatorHost(capture: capture))
    defer { tree._dispose() }
    func token() -> String? {
      let html = text(tree)
      guard let start = html.range(of: "data-phase-trigger=\"") else { return nil }
      return String(html[start.upperBound...].prefix { $0 != "\"" })
    }
    let first = token()
    #expect(first != nil && first != "")
    capture.unrelated?.wrappedValue += 1
    #expect(token() == first)
    capture.unrelated?.wrappedValue += 1
    #expect(token() == first)
  }

  // A phase whose animation has a delay publishes it, so the page holds the view before it moves on.
  @Test
  func phaseAnimationsPublishTheirDelays() {
    let delayed = Text("x").phaseAnimator([0, 1]) { content, phase in content.opacity(phase == 0 ? 1 : 0.5) } animation: { phase in
      phase == 0 ? .linear(duration: 0.2) : .linear(duration: 0.3).delay(1)
    }._render(in: _RenderContext())
    #expect(delayed.attributes["data-phase-delays"] == "0,1")
    #expect(delayed.attributes["data-phase-durations"] == "0.2,0.3")
    let plain = Text("x").phaseAnimator([0, 1]) { content, phase in content.opacity(phase == 0 ? 1 : 0.5) }._render(in: _RenderContext())
    #expect(plain.attributes["data-phase-delays"] == nil)
  }

  // In a right-to-left layout the leading edge is on the right: a move, a slide and a push come from there, a scale's anchor is
  // on the other side, and an offset, which is not relative to an edge, stays as it is.
  @Test
  func edgeTransitionsFollowTheLayoutDirection() {
    func states(_ transition: AnyTransition, _ direction: LayoutDirection) -> (String?, String?) {
      let node = Text("x").transition(transition).environment(\.layoutDirection, direction)._render(in: _RenderContext())
      func find(_ node: _RenderNode) -> _RenderNode? { node.attributes["data-transition-insert"] != nil ? node : node.children.lazy.compactMap(find).first }
      let found = find(node)
      return (found?.attributes["data-transition-insert"], found?.attributes["data-transition-remove"])
    }
    #expect(states(.move(edge: .leading), .leftToRight).0 == "translate:-100% 0px")
    #expect(states(.move(edge: .leading), .rightToLeft).0 == "translate:100% 0px")
    #expect(states(.move(edge: .trailing), .rightToLeft).0 == "translate:-100% 0px")
    #expect(states(.move(edge: .top), .rightToLeft).0 == states(.move(edge: .top), .leftToRight).0)
    // A slide enters from the leading edge and leaves towards the trailing one.
    #expect(states(.slide, .leftToRight) == ("translate:-100% 0px", "translate:100% 0px"))
    #expect(states(.slide, .rightToLeft) == ("translate:100% 0px", "translate:-100% 0px"))
    #expect(states(.offset(x: 30, y: 0), .rightToLeft).0 == states(.offset(x: 30, y: 0), .leftToRight).0)
    #expect(states(.scale(scale: 0.5, anchor: .leading), .leftToRight).0?.contains("transform-origin:0% 50%") == true)
    #expect(states(.scale(scale: 0.5, anchor: .leading), .rightToLeft).0?.contains("transform-origin:100% 50%") == true)
    // Combined with an offset, only the edge part changes side.
    #expect(states(AnyTransition.move(edge: .leading).combined(with: .offset(x: 30, y: 0)), .rightToLeft).0 == "translate:calc(30px + 100%) calc(0px + 0px)")
  }

  // Lengths and times at the edges of what a number can say are published as numbers the page reads, and nothing traps.
  @Test
  func extremeTransitionValuesArePublishedAsPlainNumbers() {
    let far = Text("x").transition(.offset(x: 1e15, y: -1e300))._render(in: _RenderContext())
    #expect(far.attributes["data-transition-insert"]?.contains("e+") == false)
    #expect(far.attributes["data-transition-insert"]?.contains("1000000000000px") == true)
    #expect(Animation.linear(duration: 1e-8)._transitionTiming == "0ms linear")
    #expect(Animation.linear(duration: 1).delay(1e-9)._transitionTiming == "1000ms linear")
    #expect(_SpringMotion(duration: 0.5, bounce: 0).cssEasing(duration: 1e18).hasPrefix("linear(0"))
  }

  // A transaction that clears an animation an ancestor's value-scoped animation armed says so to the page.
  @Test
  func clearedAnimationIsPublishedWhenNoTransactionWasCommitted() {
    let capture = ReviewCapture()
    let tree = FiberTree(ReviewClearedHost(capture: capture))
    defer { tree._dispose() }
    #expect(!text(tree).contains("data-transaction-timing=\"none\""))
    capture.level?.wrappedValue = 1
    #expect(text(tree).contains("data-transaction-timing=\"none\""))
  }

  // `.transaction(value:_:)` keeps the history of its value for real renders only.
  @Test
  func speculativeRenderDoesNotRecordTheHistoryOfAValueTransaction() {
    var context = _RenderContext()
    context._speculative = true
    _ValueTransactionModifier(value: 1, transform: { $0.animation = nil })._modifyContext(&context)
    #expect(context.stateStore._animatorValues.isEmpty)
    context._speculative = false
    _ValueTransactionModifier(value: 1, transform: { $0.animation = nil })._modifyContext(&context)
    #expect(!context.stateStore._animatorValues.isEmpty)
  }

  // A visual effect's opacity multiplies the opacity the view already has.
  @Test
  func visualEffectOpacityMultipliesTheViewsOwn() {
    var context = _RenderContext()
    let node = Text("x").opacity(0.4)._render(in: context)
    #expect(node.styles["opacity"] == "0.4")
    _EncodedVisualEffect(encoded: "opacity=0.5")._apply(to: node, context: &context)
    #expect(node.styles["opacity"] == "0.2")
    let plain = Text("y")._render(in: context)
    _EncodedVisualEffect(encoded: "opacity=0.5")._apply(to: plain, context: &context)
    #expect(plain.styles["opacity"] == "0.5")
  }

  // A geometry effect sees the size the content has: an explicit frame, else what the page measured, else the proposal.
  @Test
  func geometryEffectSizeIsTheContentsOwn() {
    var context = _RenderContext()
    context._layoutProposal = ProposedViewSize(width: 50, height: 20)
    let key = context._compactPathID + "#effect-size"
    // Both sides explicit: the proposal does not override them.
    let framed = Text("x")._render(in: context)
    framed.attributes["data-frame-w"] = "30"
    framed.attributes["data-frame-h"] = "12"
    #expect(_effectSize(node: framed, context: context) == CGSize(width: 30, height: 12))
    // Nothing measured yet: the proposal is the best guess, and the page is asked to measure (without the effect's transform).
    let intrinsic = Text("y")._render(in: context)
    #expect(_effectSize(node: intrinsic, context: context) == CGSize(width: 50, height: 20))
    #expect(intrinsic.attributes["data-geometry-untransformed"] == "local")
    #expect(intrinsic.attributes["data-geometry-change"] != nil)
    // Measured: its size, not the proposal's.
    context.stateStore._windowFrames[key] = CGRect(x: 4, y: 5, width: 80, height: 16)
    #expect(_effectSize(node: intrinsic, context: context) == CGSize(width: 80, height: 16))
    // One side explicit, the other measured.
    let half = Text("z")._render(in: context)
    half.attributes["data-frame-w"] = "30"
    #expect(_effectSize(node: half, context: context) == CGSize(width: 30, height: 16))
  }

  // A transaction that disables animations keeps the page from arming a value-scoped animation.
  @Test
  func disabledTransactionPublishesNoAnimationTiming() {
    let capture = ReviewCapture()
    let tree = FiberTree(ReviewDisabledHost(capture: capture))
    defer { tree._dispose() }
    capture.level?.wrappedValue = 1
    let html = text(tree)
    #expect(!html.contains("data-animation-timing"))
    #expect(html.contains("data-transaction-timing=\"none\""))
  }

  // The identity phase of a custom transition is how the view rests; the active phase is put over it.
  @Test
  func customTransitionRestsInItsIdentityPhase() {
    let node = Text("x").transition(ReviewHalfRest())._render(in: _RenderContext())
    #expect(node.styles["opacity"] == "0.5")
    // Appearing at 0 is 0 of the resting 0.5, relative to it.
    #expect(node.attributes["data-transition-insert"] == "opacity:0")
  }

  // An active phase brighter than the identity phase keeps its ratio, and what the identity phase put on the view is published.
  @Test
  func customTransitionKeepsRatiosAndPublishesItsRestingLook() {
    let node = Text("x").transition(ReviewBrighterThanRest())._render(in: _RenderContext())
    #expect(node.styles["opacity"] == "0.5")
    // Active 1 over a resting 0.5 is a ratio of 2, which the host multiplies by the 0.5 the view rests at.
    #expect(node.attributes["data-transition-insert"] == "opacity:2")
    #expect(node.attributes["data-transition-rest"] == "opacity:0.5")
    let tilted = Text("y").transition(ReviewTilt())._render(in: _RenderContext())
    #expect(tilted.attributes["data-transition-rest"]?.contains("transform:") == true)
    #expect(tilted.attributes["data-transition-insert"]?.contains("rotate") == true)
  }

  // A phase that leaves the opacity unset while identity sets it appears at the default 1, so its ratio to identity is kept.
  @Test
  func anOpacitySetOnlyAtIdentityStillGivesTheRatio() {
    let node = Text("x").transition(ReviewIdentityOnlyOpacity())._render(in: _RenderContext())
    #expect(node.styles["opacity"] == "0.5")
    #expect(node.attributes["data-transition-insert"] == "opacity:2")
    #expect(node.attributes["data-transition-rest"] == "opacity:0.5")
  }

  // With an identity opacity of zero the active opacity is given as it is, 1 included.
  @Test
  func activeOpacityIsAbsoluteWhenTheIdentityOpacityIsZero() {
    let half = Text("x").transition(ReviewZeroRest(active: 0.5))._render(in: _RenderContext())
    #expect(half.attributes["data-transition-rest"] == "opacity:0")
    #expect(half.attributes["data-transition-insert"] == "opacity:0.5")
    let full = Text("y").transition(ReviewZeroRest(active: 1))._render(in: _RenderContext())
    #expect(full.attributes["data-transition-insert"] == "opacity:1")
  }

  // Stacked colour multipliers keep their own matrices and references, in order: a filter between two of them does not commute.
  @Test
  func stackedColorMultipliersKeepTheirOrder() {
    let node = Text("x")
      .colorMultiply(Color(red: 1, green: 0, blue: 1))
      .blur(radius: 2)
      .colorMultiply(Color(red: 0, green: 1, blue: 1))
      ._render(in: _RenderContext())
    #expect(node.attributes["data-color-multiply"] == "1 0 1 1;0 1 1 1")
    let first = "url(#\(_colorMultiplyID([1, 0, 1, 1])))", second = "url(#\(_colorMultiplyID([0, 1, 1, 1])))"
    #expect(node.styles["filter"] == "\(first) blur(2px) \(second)")
    // And the filters of other modifiers chain as well, instead of the last one replacing the rest.
    let chained = Text("z").blur(radius: 2).contrast(0.5)._render(in: _RenderContext())
    #expect(chained.styles["filter"] == "blur(2px) contrast(0.5)")
    let single = Text("y").colorMultiply(Color(red: 1, green: 0, blue: 1))._render(in: _RenderContext())
    #expect(single.attributes["data-color-multiply"] == "1 0 1 1")
    #expect(single.styles["filter"] == first)
  }

  // A transition's own animation keeps its repetition and direction for the host.
  @Test
  func aTransitionAnimationKeepsItsRepetition() {
    let once = Text("a").transition(AnyTransition.opacity.animation(.linear(duration: 1)))._render(in: _RenderContext())
    #expect(once.attributes["data-transition-timing"] == "1000ms linear")
    let counted = Text("b").transition(AnyTransition.opacity.animation(.linear(duration: 1).repeatCount(3, autoreverses: false)))._render(in: _RenderContext())
    #expect(counted.attributes["data-transition-timing"] == "1000ms linear repeat:3 normal")
    let forever = Text("c").transition(.asymmetric(
      insertion: AnyTransition.opacity.animation(.linear(duration: 1).repeatForever()),
      removal: AnyTransition.opacity.animation(.linear(duration: 2).repeatCount(2))
    ))._render(in: _RenderContext())
    #expect(forever.attributes["data-transition-insert-timing"] == "1000ms linear repeat:infinite alternate")
    #expect(forever.attributes["data-transition-remove-timing"] == "2000ms linear repeat:2 alternate")
  }

  // The options of a symbol replace (speed, repeats) travel with the content transition to the host.
  @Test
  func aSymbolReplaceKeepsItsOptions() {
    let plain = Image(systemName: "star").contentTransition(.symbolEffect(.replace))._render(in: _RenderContext())
    #expect(plain.attributes["data-content-transition"] == "symbol-effect")
    #expect(plain.attributes["data-content-transition-speed"] == nil)
    #expect(plain.attributes["data-content-transition-repeat"] == nil)
    let tuned = Image(systemName: "star").contentTransition(.symbolEffect(.replace, options: .speed(2).repeat(3)))._render(in: _RenderContext())
    #expect(tuned.attributes["data-content-transition-speed"] == "2.0")
    #expect(tuned.attributes["data-content-transition-repeat"] == "3")
  }

  // The options of a symbol effect transition (speed, repeats) travel with the transition to the host.
  @Test
  func aSymbolEffectTransitionKeepsItsOptions() {
    let plain = Text("a").transition(.symbolEffect(.appear))._render(in: _RenderContext())
    #expect(plain.attributes["data-transition-speed"] == nil)
    #expect(plain.attributes["data-transition-repeat"] == nil)
    let tuned = Text("b").transition(.symbolEffect(.appear, options: .speed(2).repeat(3)))._render(in: _RenderContext())
    #expect(tuned.attributes["data-transition-speed"] == "2.0")
    #expect(tuned.attributes["data-transition-repeat"] == "3")
    // Combined with another transition, or as one side of an asymmetric one, it keeps them too.
    let symbol = AnyTransition(SymbolEffectTransition.symbolEffect(.appear, options: .speed(2).repeat(3)))
    for transition in [symbol.combined(with: .opacity), AnyTransition.opacity.combined(with: symbol), .asymmetric(insertion: symbol, removal: .opacity), .asymmetric(insertion: .opacity, removal: symbol)] {
      let node = Text("c").transition(transition)._render(in: _RenderContext())
      #expect(node.attributes["data-transition-speed"] == "2.0")
      #expect(node.attributes["data-transition-repeat"] == "3")
    }
  }

  // An animation that repeats and autoreverses says so in the CSS timing a transaction publishes, for the host to play it.
  @Test
  func aRepeatingAnimationPublishesItsDirection() {
    #expect(Animation.linear(duration: 1).repeatCount(3).cssValue.contains("/* repeat 3 */ /* alternate */"))
    #expect(!Animation.linear(duration: 1).repeatCount(3, autoreverses: false).cssValue.contains("alternate"))
    #expect(Animation.linear(duration: 1).repeatForever().cssValue.contains("/* infinite */ /* alternate */"))
    #expect(!Animation.linear(duration: 1).cssValue.contains("/*"))
  }

  // A view that leaves the tree takes the animated values Swift kept for it along.
  @Test
  func animatedValuesLeaveWithTheirView() {
    let capture = ReviewShownCapture()
    let tree = FiberTree(ReviewDisappearingHost(capture: capture))
    defer { tree._dispose() }
    let store = tree.root.stateStore
    #expect(text(tree).contains("shown"))
    #expect(!store._animatorValues.isEmpty)
    capture.shown?.wrappedValue = false
    #expect(!text(tree).contains("shown"))
    #expect(store._animatorValues.isEmpty)
  }

  // Retargeting a custom animation asks it whether it takes the interrupted run over, and the run continues with the
  // state its merge left.
  @Test
  func retargetingAsksTheCustomAnimationToMerge() {
    ReviewMergeProbe.seen = []
    let capture = ReviewCapture()
    let tree = FiberTree(ReviewMergingHost(capture: capture))
    defer { tree._dispose() }
    capture.level?.wrappedValue = 10
    AnimatorReviewTests.now += 0.2
    _ = tree._hostTimelineTick()
    capture.level?.wrappedValue = 20
    AnimatorReviewTests.now += 0.2
    _ = tree._hostTimelineTick()
    #expect(ReviewMergeProbe.seen.first == 0)
    #expect(ReviewMergeProbe.seen.last == 1)
  }

  // A custom animation decides whether it takes over the one it interrupts, and the state it updates is kept.
  @Test
  func customAnimationDecidesItsOwnMerge() {
    var context = AnimationContext<Double>()
    #expect(Animation(ReviewMerging()).shouldMerge(previous: .default, value: 4.0, time: 0.25, context: &context))
    #expect(context.state[ReviewMergeCount.self] == 1)
    #expect(!Animation(ReviewRamp()).shouldMerge(previous: .default, value: 4.0, time: 0.25, context: &context))
    #expect(!Animation.linear(duration: 1).shouldMerge(previous: .default, value: 4.0, time: 0.25, context: &context))
    #expect(Animation.spring(duration: 1).shouldMerge(previous: .default, value: 4.0, time: 0.25, context: &context))
  }
}

private struct ReviewBrighterThanRest: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase == .identity ? 0.5 : 1)
  }
}

private struct ReviewIdentityOnlyOpacity: Transition {
  @ViewBuilder func body(content: Content, phase: TransitionPhase) -> some View {
    if phase == .identity { content.opacity(0.5) } else { content }
  }
}

private struct ReviewTilt: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.rotationEffect(.degrees(phase == .identity ? 10 : 20))
  }
}

private struct ReviewZeroRest: Transition {
  let active: Double
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase == .identity ? 0 : active)
  }
}

private struct ReviewHalfRest: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase == .identity ? 0.5 : 0)
  }
}

private struct ReviewDisabledHost: View {
  @State var level = 0.0
  let capture: ReviewCapture
  var body: some View {
    capture.level = $level
    return VStack { Text("x \(Int(level))").animation(.linear(duration: 1), value: level) }.transaction { $0.disablesAnimations = true }
  }
}

private struct ReviewClearedHost: View {
  @State var level = 0.0
  let capture: ReviewCapture
  var body: some View {
    capture.level = $level
    return VStack { Text("x \(Int(level))").transaction { $0.animation = nil } }.animation(.linear(duration: 1), value: level)
  }
}

private struct ReviewScopedHost: View {
  @State var level = 0.0
  let capture: ReviewCapture
  var body: some View {
    capture.level = $level
    return ReviewMeter(level: level).animation(.linear(duration: 1)) { content in content.opacity(0.5) }
  }
}

private struct ReviewOptOutHost: View {
  @State var level = 0.0
  let capture: ReviewCapture
  var body: some View {
    capture.level = $level
    return ReviewMeter(level: level).animation(nil, value: level)
  }
}

private final class ReviewShownCapture { var shown: Binding<Bool>? }

/// Counts the merges that reached it, and reports the count it is evaluated with.
private struct ReviewMergeProbe: CustomAnimation {
  nonisolated(unsafe) static var seen: [Int] = []
  func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
    Self.seen.append(context.state[ReviewMergeCount.self])
    return time < 1 ? value.scaled(by: time) : nil
  }
  func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>) -> Bool {
    context.state[ReviewMergeCount.self] += 1
    return true
  }
}

private struct ReviewMergingHost: View {
  @State var level = 0.0
  let capture: ReviewCapture
  var body: some View {
    capture.level = $level
    return ReviewMeter(level: level).animation(Animation(ReviewMergeProbe()), value: level)
  }
}

private struct ReviewDisappearingHost: View {
  @State var shown = true
  let capture: ReviewShownCapture
  var body: some View {
    capture.shown = $shown
    return VStack {
      if shown { Text("shown").animation(.linear(duration: 1), value: shown) }
    }
  }
}

private struct ReviewProbeKey: EnvironmentKey {
  static let defaultValue = false
}

private extension EnvironmentValues {
  var reviewProbe: Bool {
    get { self[ReviewProbeKey.self] }
    set { self[ReviewProbeKey.self] = newValue }
  }
}

private struct ReviewFixedVelocity: CustomAnimation {
  func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? { value.scaled(by: time) }
  func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? { value.scaled(by: 5) }
}

/// Records the environment a custom animation is evaluated in.
private struct ReviewEnvironmentProbe: CustomAnimation {
  nonisolated(unsafe) static var seen: [Bool] = []
  func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
    Self.seen.append(context.environment.reviewProbe)
    return time < 1 ? value.scaled(by: time) : nil
  }
}

private struct ReviewEnvironmentMeter: View, Animatable {
  var level: Double
  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }
  var body: some View { Text("level \(Int(level.rounded()))") }
}

private struct ReviewEnvironmentHost: View {
  @State var level = 0.0
  let capture: ReviewCapture
  var body: some View {
    capture.level = $level
    return ReviewEnvironmentMeter(level: level).animation(Animation(ReviewEnvironmentProbe()), value: level)
  }
}

private struct ReviewMergeCount: AnimationStateKey {
  static let defaultValue = 0
}

/// Takes over any animation it interrupts, and counts how often it was asked.
private struct ReviewMerging: CustomAnimation {
  func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? { nil }
  func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>) -> Bool {
    context.state[ReviewMergeCount.self] += 1
    return true
  }
}

private struct ReviewRamp: CustomAnimation {
  func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
    guard time < 0.5 else { return nil }
    return value.scaled(by: time / 0.5)
  }
}

/// Moves at one unit of value per second, whatever the change is.
private struct ReviewOneUnitPerSecond: CustomAnimation {
  func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
    let distance = value.magnitudeSquared.squareRoot()
    guard distance > 0, time < distance else { return nil }
    return value.scaled(by: time / distance)
  }
}

private final class ReviewCapture { var level: Binding<Double>? }

private struct ReviewMeter: View, Animatable {
  var level: Double
  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }
  var body: some View { Text("level \(Int(level.rounded()))") }
}

private struct ReviewFlashTrigger: Equatable { var page: Int; var section: String }

private final class ReviewFlashCapture { var trigger: Binding<ReviewFlashTrigger>?; var unrelated: Binding<Int>? }

private struct ReviewFlashHost: View {
  @State var trigger = ReviewFlashTrigger(page: 1, section: "a")
  @State var unrelated = 0
  let capture: ReviewFlashCapture
  var body: some View {
    capture.trigger = $trigger
    capture.unrelated = $unrelated
    return Text("rows \(unrelated)").scrollIndicatorsFlash(trigger: trigger)
  }
}

private struct ReviewAnimatorHost: View {
  @State var trigger = ReviewFlashTrigger(page: 1, section: "a")
  @State var unrelated = 0
  let capture: ReviewFlashCapture
  var body: some View {
    capture.trigger = $trigger
    capture.unrelated = $unrelated
    return VStack {
      Text("rows \(unrelated)").phaseAnimator([0, 1], trigger: trigger) { content, phase in content.opacity(phase == 0 ? 1 : 0.5) }
      PhaseAnimator([0, 1], trigger: trigger) { phase in Text("phase").opacity(phase == 0 ? 1 : 0.5) }
      Text("key").keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, value in content.opacity(1 - value) } keyframes: { _ in
        LinearKeyframe(0.5, duration: 0.2)
      }
    }
  }
}

private struct ReviewNestedAnimatorHost: View {
  @State var unrelated = 0
  let capture: ReviewFlashCapture
  var body: some View {
    capture.unrelated = $unrelated
    return VStack {
      Text("rows \(unrelated)")
      KeyframeAnimator(initialValue: 0.0) { value in
        VStack {
          Text("child").phaseAnimator([0, 1], trigger: value) { content, phase in content.opacity(phase == 0 ? 1 : 0.5) }
        }
      } keyframes: { _ in
        LinearKeyframe(1.0, duration: 0.5)
      }
    }
  }
}

private struct ReviewStackedHost: View {
  @State var level = 0.0
  @State var other = 3
  let capture: ReviewCapture
  var body: some View {
    capture.level = $level
    return ReviewMeter(level: level).animation(.linear(duration: 1), value: level).animation(.linear(duration: 5), value: other)
  }
}

private struct ReviewValueHost: View {
  @State var level = 0.0
  let capture: ReviewCapture
  var body: some View {
    capture.level = $level
    return ReviewMeter(level: level).animation(.linear(duration: 1), value: level)
  }
}
