// What Swift animates itself: the `animatableData` of views, modifiers, shapes and geometry effects, which only Swift
// can interpolate (their body or path is Swift code). SwiftUI renders such a value at every frame of its animation;
// so does this.
//
// When the data a view renders with changes in a commit whose transaction animates (`withAnimation`, a `.transaction`
// or `.animation(_:value:)` above it), the view keeps showing the value it showed and starts moving it to the new one
// with the transaction's animation. While it moves, its node carries a timeline that runs on animation frames: the page
// calls `timeline_tick` once a frame, which renders the view's owner again (`FiberTree._hostTimelineTick`), and the view
// renders the value the animation has reached at that time. The timeline goes away when the animation finishes.

/// The clock tests install in place of the page's, in seconds. A global initialized with a closure is not linkable from
/// another module in Embedded Swift (the closure is not emitted where the specialization that reads it lands), so the
/// default is a function instead.
nonisolated(unsafe) package var _animationClockOverride: (() -> Double)? = nil

/// The clock animations read, in seconds: the browser's `Date`, unless a test installed its own.
func _animationClock() -> Double {
  if let clock = _animationClockOverride { return clock() }
  return Date().timeIntervalSince1970
}

/// One value Swift animates, kept between renders under its fiber path.
struct _AnimatedValue<Value: VectorArithmetic> {
  /// One run of an animation: from where the value was to the target it was given.
  struct Run {
    var from: Value
    var change: Value
    var animation: Animation
    var start: Double
    var context = AnimationContext<Double>()

    /// The value at `now`, and whether the run is still under way.
    mutating func value(at now: Double) -> (value: Value, running: Bool) {
      let distance = change.magnitudeSquared.squareRoot()
      guard let fraction = animation._fraction(at: now - start, change: distance, context: &context) else { return (from + change, false) }
      return (from + change.scaled(by: fraction), true)
    }
  }

  var target: Value
  var run: Run?
  /// The run a spring interrupted, which it blends from for its blend duration.
  var interrupted: Run?

  /// The value to show at `now`, and whether it is still moving.
  mutating func value(at now: Double) -> (value: Value, moving: Bool) {
    guard var current = run else { return (target, false) }
    var (value, running) = current.value(at: now)
    run = running ? current : nil
    if var previous = interrupted {
      let blend = current.animation._blendDuration
      let elapsed = now - current.start
      if running, blend > 0, elapsed < blend {
        let old = previous.value(at: now).value
        interrupted = previous
        value = old.interpolated(towards: value, amount: elapsed / blend)
      } else {
        interrupted = nil
      }
    }
    return (running ? value : target, running)
  }
}

@MainActor enum _Animator {
  /// The value of `target` to render at `key` now: the target itself, or where an animation towards it has reached.
  static func present<Value: VectorArithmetic>(_ target: Value, key: String, context: _RenderContext) -> (value: Value, moving: Bool) {
    let store = context.stateStore
    let now = _animationClock()
    // A speculative render (the hovered look of a hover effect, learned and then discarded) must not change what the real
    // renders animate from. It shows what the real one shows: the value an animation under way has reached, read from a copy,
    // or the target when there is none or when the flip it renders changes the data.
    if context._speculative {
      guard var state = store._animatorValues.value(for: key, as: _AnimatedValue<Value>.self), state.target == target else { return (target, false) }
      let result = state.value(at: now)
      return (result.value, result.moving)
    }
    guard var state = store._animatorValues.value(for: key, as: _AnimatedValue<Value>.self) else {
      store._animatorValues.set(_AnimatedValue(target: target), for: key)
      return (target, false)
    }
    if state.target != target {
      let shown = state.value(at: now).value
      let transaction = context._transaction
      if let animation = transaction?.effectiveAnimation, !context.environment.accessibilityReduceMotion {
        // A spring takes the value over where it is; another curve starts from there too, so nothing jumps.
        if let running = state.run, animation._blendDuration > 0 { state.interrupted = running } else { state.interrupted = nil }
        // The new animation decides whether it takes the run it interrupts over: a custom one then continues with the
        // state its merge left, instead of starting from none.
        var runContext = AnimationContext<Double>(environment: context.environment)
        if let running = state.run {
          var previous = running.context
          if animation._shouldMerge(previous: running.animation, change: (target - shown).magnitudeSquared.squareRoot(), time: now - running.start, context: &previous) {
            runContext = AnimationContext<Double>(state: previous.state, isLogicallyComplete: false, environment: context.environment)
          }
        }
        state.run = _AnimatedValue.Run(from: shown, change: target - shown, animation: animation, start: now, context: runContext)
      } else {
        state.run = nil
        state.interrupted = nil
      }
      state.target = target
    }
    let result = state.value(at: now)
    store._animatorValues.set(state, for: key)
    return result
  }

  /// Keeps `node` rendering at every animation frame while what it shows is moving.
  static func mark(_ node: _RenderNode, key: String, moving: Bool) {
    guard moving else { return }
    node._timeline = _TimelineDescriptor(identifier: key, interval: nil, usesAnimationFrame: true, paused: false, nextDate: nil)
    // "animation", not "true": the page runs it on animation frames like a TimelineView, but the element stays one whose
    // children transitions and siblings' moves play (a TimelineView owns its motion).
    node.attributes["data-timeline-view"] = "animation"
    node.attributes["data-timeline-id"] = key
    node.attributes["data-timeline-cadence"] = "live"
    node.attributes["data-timeline-animation-frame"] = "true"
    // The styles the node has now are what the animated data draws; a modifier applied outside adds its own after this, and
    // the page gives those the transaction's animation like any other (`data-timeline-driven`).
    node.attributes["data-timeline-driven"] = node.styles.keys.sorted().joined(separator: ",")
    node.attributes["data-timeline-paused"] = "false"
  }
}

/// Whether a type animates data: false for the `EmptyAnimatableData` of everything that does not, which then renders
/// without looking anything up.
public extension Animatable {
  static var _swiftUIWebAnimates: Bool { true }
}

public extension Animatable where AnimatableData == EmptyAnimatableData {
  static var _swiftUIWebAnimates: Bool { false }
}

// MARK: Views

/// An `Animatable` view renders the data it shows: its body with the animatable data an animation has reached.
///
/// Nonisolated, as the default `_render` is: a main-actor witness would make a main-actor view's conformance to
/// `View` isolated, and the generic code that renders a parent's body would not use it.
public extension View where Self: Animatable {
  static var _swiftUIWebRendersItself: Bool { Self._swiftUIWebAnimates }

  nonisolated func _render(in context: _RenderContext) -> _RenderNode {
    nonisolated(unsafe) let view = self
    return _assumeMainActor { AnyView(_ownerBoundaryOf: _AnimatedView(view: view))._render(in: context) }
  }
}

/// The owner of an animatable view, so the frames of its animation render it again.
struct _AnimatedView<Content: View & Animatable>: _OwnerBoundaryContent {
  let view: Content

  @MainActor func _renderOwnerBoundary(in context: _RenderContext) -> _RenderNode {
    let key = context._compactPathID + "#animatable"
    let (data, moving) = _Animator.present(view.animatableData, key: key, context: context)
    var shown = view
    shown.animatableData = data
    let node = shown.body._render(in: context)
    _Animator.mark(node, key: key, moving: moving)
    return node
  }
}

// MARK: Modifiers

/// A modifier that animates its data, as `GeometryEffect`s do; its body and effect render with the data an animation
/// has reached.
public protocol AnimatableModifier: Animatable, ViewModifier {}

public extension ViewModifier {
  /// The modifier as it renders now, and whether an animation is moving it. Nothing moves a modifier that has no
  /// animatable data.
  @MainActor func _swiftUIWebPresented(in context: _RenderContext) -> (modifier: Self, moving: Bool) { (self, false) }
}

public extension ViewModifier where Self: Animatable {
  @MainActor func _swiftUIWebPresented(in context: _RenderContext) -> (modifier: Self, moving: Bool) {
    guard Self._swiftUIWebAnimates else { return (self, false) }
    let (data, moving) = _Animator.present(animatableData, key: context._modifierStateKey("#modifier"), context: context)
    var shown = self
    shown.animatableData = data
    return (shown, moving)
  }
}

// MARK: Geometry effects

/// A 3x3 projective transform of the plane, as `GeometryEffect`s return: a point (x, y) maps to
/// ((m11 x + m21 y + m31) / w, (m12 x + m22 y + m32) / w) with w = m13 x + m23 y + m33.
@frozen public struct ProjectionTransform {
  public var m11: CGFloat = 1, m12: CGFloat = 0, m13: CGFloat = 0
  public var m21: CGFloat = 0, m22: CGFloat = 1, m23: CGFloat = 0
  public var m31: CGFloat = 0, m32: CGFloat = 0, m33: CGFloat = 1

  public init() {}

  public init(_ m: CGAffineTransform) {
    m11 = m.a; m12 = m.b; m21 = m.c; m22 = m.d; m31 = m.tx; m32 = m.ty
  }

  public var isIdentity: Bool {
    m11 == 1 && m12 == 0 && m13 == 0 && m21 == 0 && m22 == 1 && m23 == 0 && m31 == 0 && m32 == 0 && m33 == 1
  }

  public var isAffine: Bool { m13 == 0 && m23 == 0 && m33 == 1 }

  /// Inverts the transform in place; false (and unchanged) when it has no inverse.
  public mutating func invert() -> Bool {
    let c11 = m22 * m33 - m23 * m32, c12 = m13 * m32 - m12 * m33, c13 = m12 * m23 - m13 * m22
    let c21 = m23 * m31 - m21 * m33, c22 = m11 * m33 - m13 * m31, c23 = m13 * m21 - m11 * m23
    let c31 = m21 * m32 - m22 * m31, c32 = m12 * m31 - m11 * m32, c33 = m11 * m22 - m12 * m21
    let determinant = m11 * c11 + m12 * c21 + m13 * c31
    guard determinant != 0, determinant.isFinite else { return false }
    let s = 1 / determinant
    m11 = c11 * s; m12 = c12 * s; m13 = c13 * s
    m21 = c21 * s; m22 = c22 * s; m23 = c23 * s
    m31 = c31 * s; m32 = c32 * s; m33 = c33 * s
    return true
  }

  public func inverted() -> ProjectionTransform {
    var copy = self
    return copy.invert() ? copy : self
  }

  /// This transform, then `rhs`.
  public func concatenating(_ rhs: ProjectionTransform) -> ProjectionTransform {
    var result = ProjectionTransform()
    result.m11 = m11 * rhs.m11 + m12 * rhs.m21 + m13 * rhs.m31
    result.m12 = m11 * rhs.m12 + m12 * rhs.m22 + m13 * rhs.m32
    result.m13 = m11 * rhs.m13 + m12 * rhs.m23 + m13 * rhs.m33
    result.m21 = m21 * rhs.m11 + m22 * rhs.m21 + m23 * rhs.m31
    result.m22 = m21 * rhs.m12 + m22 * rhs.m22 + m23 * rhs.m32
    result.m23 = m21 * rhs.m13 + m22 * rhs.m23 + m23 * rhs.m33
    result.m31 = m31 * rhs.m11 + m32 * rhs.m21 + m33 * rhs.m31
    result.m32 = m31 * rhs.m12 + m32 * rhs.m22 + m33 * rhs.m32
    result.m33 = m31 * rhs.m13 + m32 * rhs.m23 + m33 * rhs.m33
    return result
  }

  public static func == (a: ProjectionTransform, b: ProjectionTransform) -> Bool {
    a.m11 == b.m11 && a.m12 == b.m12 && a.m13 == b.m13 && a.m21 == b.m21 && a.m22 == b.m22 && a.m23 == b.m23 &&
      a.m31 == b.m31 && a.m32 == b.m32 && a.m33 == b.m33
  }

  /// The CSS `matrix3d()` of the transform, about the top-leading corner.
  package var _cssMatrix: String {
    let values: [CGFloat] = [m11, m12, 0, m13, m21, m22, 0, m23, 0, 0, 1, 0, m31, m32, 0, m33]
    return "matrix3d(" + values.map { _transitionNumber(Double($0)) }.joined(separator: ",") + ")"
  }
}

extension ProjectionTransform: Equatable, Sendable {}

/// A modifier that moves its content by a projective transform of its size, which can animate. It does not change
/// the layout: the content keeps its place and is drawn transformed.
public nonisolated protocol GeometryEffect: Animatable, ViewModifier where Self.Body == Never {
  nonisolated func effectValue(size: CGSize) -> ProjectionTransform
}

/// A primitive modifier (a geometry effect) has no body: it draws its content itself.
public extension ViewModifier where Self.Body == Never {
  @MainActor @preconcurrency func body(content: Self.Content) -> Self.Body {
    fatalError("A primitive modifier draws its content itself; it has no body")
  }
}

public extension GeometryEffect {

  /// The effect, ignored by layout: already the case for every geometry effect here, which only draws transformed.
  nonisolated func ignoredByLayout() -> _IgnoredByLayoutEffect<Self> { _IgnoredByLayoutEffect(self) }

  @MainActor func _swiftUIWebRenderBody(content: Content, in context: _RenderContext) -> _RenderNode {
    content._render(in: context)
  }

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    _applyProjection(effectValue(size: _effectSize(node: node, context: context)), to: node)
  }
}

/// A geometry effect that layout ignores.
@frozen public struct _IgnoredByLayoutEffect<Base>: GeometryEffect where Base: GeometryEffect {
  public var base: Base
  public init(_ base: Base) { self.base = base }
  public typealias AnimatableData = Base.AnimatableData
  public var animatableData: Base.AnimatableData {
    get { base.animatableData }
    set { base.animatableData = newValue }
  }
  public func effectValue(size: CGSize) -> ProjectionTransform { base.effectValue(size: size) }
}

public extension ViewModifier {
  /// How the modifier renders its content: through `body(content:)`, except for geometry effects, which draw it
  /// transformed.
  @MainActor func _swiftUIWebRenderBody(content: Content, in context: _RenderContext) -> _RenderNode {
    body(content: content)._render(in: context)
  }
}

/// The size a geometry effect sees, which is the size the content has: an explicit frame says it. Content sized by itself is
/// measured by the page once it is laid out (without the effect's own transform), and the effect is evaluated again when that
/// size arrives; until then the frame the layout proposes is the best guess. A proposal is not the resolved size, so it never
/// overrides either.
@MainActor func _effectSize(node: _RenderNode, context: _RenderContext) -> CGSize {
  func explicit(_ attribute: String) -> Double? {
    guard let text = node.attributes[attribute], let value = Double(text), value.isFinite, value > 0 else { return nil }
    return value
  }
  func proposed(_ value: Double?) -> Double {
    guard let value, value.isFinite, value > 0 else { return 0 }
    return value
  }
  let width = explicit("data-frame-w"), height = explicit("data-frame-h")
  if let width, let height { return CGSize(width: width, height: height) }
  // "local": the page hands back the size the content lays out at, whatever scale or rotation is above it.
  node.attributes["data-geometry-untransformed"] = "local"
  let key = context._compactPathID + "#effect-size"
  _measureWindowFrame(of: node, key: key, store: context.stateStore, owner: context._renderOwnerToken)
  if let measured = context.stateStore._windowFrames[key], measured.width > 0 || measured.height > 0 {
    return CGSize(width: width ?? measured.width, height: height ?? measured.height)
  }
  return CGSize(width: width ?? proposed(context._layoutProposal?.width), height: height ?? proposed(context._layoutProposal?.height))
}

/// Draws `node` transformed by `transform` about its top-leading corner, after the transforms it already has.
@MainActor func _applyProjection(_ transform: ProjectionTransform, to node: _RenderNode) {
  guard !transform.isIdentity else { return }
  // The element's other transforms turn about its transform origin (the center unless an anchor moved it); the
  // projection is about the top-leading corner, so it is wrapped in a move to that corner and back.
  let origin = node.styles["transform-origin"] ?? "50% 50%"
  let parts = origin.split(separator: " ").map(String.init)
  let x = parts.first ?? "50%", y = parts.count > 1 ? parts[1] : "50%"
  let projection = "translate(calc(-1 * \(x)), calc(-1 * \(y))) \(transform._cssMatrix) translate(\(x), \(y))"
  if let existing = node.styles["transform"], !existing.isEmpty, existing != "none" {
    node.styles["transform"] = projection + " " + existing
  } else {
    node.styles["transform"] = projection
  }
}

public extension View {
  /// Draws the view transformed by `transform`, about its top-leading corner, without changing its layout.
  nonisolated func projectionEffect(_ transform: ProjectionTransform) -> some View {
    _modified(_ProjectionEffectModifier(transform: transform))
  }
}

nonisolated struct _ProjectionEffectModifier: ViewModifier {
  let transform: ProjectionTransform
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) { _applyProjection(transform, to: node) }
}

// MARK: Shapes

/// The owner of a shape with animatable data: it draws the shape with the data its animation has reached.
struct _AnimatedShape<S: Shape>: _OwnerBoundaryContent {
  let shape: S
  let draw: @MainActor (S, _RenderContext) -> _RenderNode

  @MainActor func _renderOwnerBoundary(in context: _RenderContext) -> _RenderNode {
    let key = context._compactPathID + "#shape"
    let (data, moving) = _Animator.present(shape.animatableData, key: key, context: context)
    var shown = shape
    shown.animatableData = data
    let node = draw(shown, context)
    _Animator.mark(node, key: key, moving: moving)
    return node
  }
}
