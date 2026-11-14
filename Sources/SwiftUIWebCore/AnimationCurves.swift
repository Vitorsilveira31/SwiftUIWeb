// Animation curves Swift evaluates itself, and SwiftUI's custom animation API.
//
// The browser plays what it can animate with CSS (Tools/embedded-dom.js); Swift evaluates the same curves for what only
// Swift can interpolate: `Animatable` data of views, modifiers, shapes and geometry effects (`Animator.swift`), and custom
// animations, which are sampled here into the CSS easing the browser plays.

/// A curve of an `Animation` in a form Swift can evaluate.
package enum _AnimationCurve: Hashable, Sendable {
  /// A cubic Bézier from (0, 0) to (1, 1) with these control points (CSS's `cubic-bezier()`).
  case bezier(Double, Double, Double, Double)
  case spring(_SpringMotion)
  case custom(_CustomAnimationBox)

  /// The curve a CSS keyword names; anything else eases in and out.
  static func named(_ timingFunction: String) -> _AnimationCurve {
    switch timingFunction {
    case "linear": return .bezier(0, 0, 1, 1)
    case "ease": return .bezier(0.25, 0.1, 0.25, 1)
    case "ease-in": return .bezier(0.42, 0, 1, 1)
    case "ease-out": return .bezier(0, 0, 0.58, 1)
    default: return .bezier(0.42, 0, 0.58, 1)
    }
  }

  /// The curve's value at `progress` (0...1) of an iteration lasting `duration` seconds.
  func value(at progress: Double, duration: Double) -> Double {
    switch self {
    case let .bezier(x1, y1, x2, y2): return _unitBezier(x1, y1, x2, y2, at: progress)
    case .spring(let motion): return progress >= 1 ? 1 : motion.value(at: progress * duration)
    case .custom: return progress
    }
  }
}

/// The y of the cubic Bézier through (0, 0), (x1, y1), (x2, y2), (1, 1) at `x`, found by Newton's method with bisection
/// as a fallback (as WebKit's UnitBezier does).
package func _unitBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, at x: Double) -> Double {
  if x <= 0 { return 0 }
  if x >= 1 { return 1 }
  let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
  let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
  func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
  func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
  func slopeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }
  var t = x
  for _ in 0..<8 {
    let error = sampleX(t) - x
    if (error < 0 ? -error : error) < 1e-7 { return sampleY(t) }
    let slope = slopeX(t)
    if (slope < 0 ? -slope : slope) < 1e-6 { break }
    t -= error / slope
  }
  var low = 0.0, high = 1.0
  t = x
  for _ in 0..<40 {
    let value = sampleX(t)
    let error = value - x
    if (error < 0 ? -error : error) < 1e-7 { break }
    if value < x { low = t } else { high = t }
    t = (low + high) / 2
  }
  return sampleY(t)
}

// MARK: Custom animations

/// A custom animation: what `Animation(_:)` wraps.
@preconcurrency public protocol CustomAnimation: Hashable, Sendable {
  /// The value at `time` seconds into the animation of `value` (the whole change), or nil once it has finished.
  nonisolated func animate<V>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? where V: VectorArithmetic
  /// The velocity at `time`; nil when the animation does not know it.
  nonisolated func velocity<V>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? where V: VectorArithmetic
  /// Whether this animation, interrupting `previous`, takes it over instead of running beside it.
  nonisolated func shouldMerge<V>(previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>) -> Bool where V: VectorArithmetic
}

public extension CustomAnimation {
  func velocity<V>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? where V: VectorArithmetic { nil }
  func shouldMerge<V>(previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>) -> Bool where V: VectorArithmetic { false }
}

/// A key for state a custom animation keeps between the times it is evaluated.
public protocol AnimationStateKey {
  associatedtype Value
  static var defaultValue: Self.Value { get }
}

/// What a custom animation keeps while it runs, by key.
public struct AnimationState<Value> where Value: VectorArithmetic {
  // Keyed by the type of the key, not of `Value`: a context converted with `withState` keeps what was stored.
  var storage = _TypedValueStorage<ObjectIdentifier>()

  public init() {}

  public subscript<K>(key: K.Type) -> K.Value where K: AnimationStateKey {
    get { storage.value(for: _storedTypeID(key), as: K.Value.self) ?? K.defaultValue }
    set { storage.set(newValue, for: _storedTypeID(key)) }
  }
}

/// What a custom animation is evaluated in: its state, whether it is logically complete, and the environment of the
/// view it animates.
public struct AnimationContext<Value> where Value: VectorArithmetic {
  public var state: AnimationState<Value>
  public var isLogicallyComplete: Bool
  private let environmentValue: EnvironmentValues?

  init(state: AnimationState<Value> = AnimationState(), isLogicallyComplete: Bool = false, environment: EnvironmentValues? = nil) {
    self.state = state
    self.isLogicallyComplete = isLogicallyComplete
    environmentValue = environment
  }

  public var environment: EnvironmentValues { environmentValue ?? EnvironmentValues() }

  /// The same context with another state.
  public func withState<T>(_ state: AnimationState<T>) -> AnimationContext<T> where T: VectorArithmetic {
    AnimationContext<T>(state: state, isLogicallyComplete: isLogicallyComplete, environment: environmentValue)
  }

  /// The same context for values of another type, keeping its state.
  func converted<T: VectorArithmetic>(to type: T.Type = T.self) -> AnimationContext<T> {
    var state = AnimationState<T>()
    state.storage = self.state.storage
    return AnimationContext<T>(state: state, isLogicallyComplete: isLogicallyComplete, environment: environmentValue)
  }
}

/// A custom animation, erased without an existential (Embedded Swift has none): it is evaluated for the magnitude of the
/// change being animated (a `Double` value whose `magnitudeSquared` is that change's), and the fraction of the change it
/// makes is what `Animation.animate` scales to the value being animated.
package final class _CustomAnimationBox: Hashable, @unchecked Sendable {
  let hash: Int
  private let typeID: ObjectIdentifier
  private let evaluate: (Double, Double, inout AnimationContext<Double>) -> Double?
  private let speed: (Double, Double, AnimationContext<Double>) -> Double?
  private let merges: (Animation, Double, Double, inout AnimationContext<Double>) -> Bool
  /// The base, typed-stored, and a comparison against another box's base: it reads that base as `A` (nil for another type)
  /// and compares it with `==`, so the erased box can still tell two values apart when their hashes collide.
  private let payload: _TypedValueStorage<Int>
  private let baseEquals: (_TypedValueStorage<Int>) -> Bool

  init<A: CustomAnimation>(_ base: A) {
    hash = base.hashValue
    typeID = _storedTypeID(A.self)
    var stored = _TypedValueStorage<Int>()
    stored.set(base, for: 0)
    payload = stored
    baseEquals = { other in
      guard let otherBase = other.value(for: 0, as: A.self) else { return false }
      return base == otherBase
    }
    evaluate = { value, time, context in base.animate(value: value, time: time, context: &context) }
    speed = { value, time, context in base.velocity(value: value, time: time, context: context) }
    merges = { previous, value, time, context in base.shouldMerge(previous: previous, value: value, time: time, context: &context) }
  }

  func animate(_ value: Double, _ time: Double, _ context: inout AnimationContext<Double>) -> Double? { evaluate(value, time, &context) }
  func velocity(_ value: Double, _ time: Double, _ context: AnimationContext<Double>) -> Double? { speed(value, time, context) }
  func shouldMerge(_ previous: Animation, _ value: Double, _ time: Double, _ context: inout AnimationContext<Double>) -> Bool {
    merges(previous, value, time, &context)
  }

  /// The animation as a CSS easing: its fraction sampled 60 times a second until it finishes (ten seconds at most).
  func sampled() -> (easing: String, duration: Double) {
    var context = AnimationContext<Double>()
    var values: [Double] = []
    let step = 1.0 / 60
    var time = step
    while time <= 10, let value = evaluate(1, time, &context) {
      values.append(value)
      time += step
    }
    let duration = Double(values.count + 1) * step
    var easing = "linear(0"
    // At most 120 samples, evenly picked: the browser interpolates between them.
    let stride = max(1, (values.count + 119) / 120)
    var index = stride - 1
    while index < values.count {
      easing += "," + _easingNumber(values[index])
      index += stride
    }
    easing += ",1)"
    return (easing, duration)
  }

  /// Equal when the bases are equal (the same type, and `==` on the values), as SwiftUI compares custom animations. The hash
  /// is only a fast path: two different custom animations can share one.
  package static func == (lhs: _CustomAnimationBox, rhs: _CustomAnimationBox) -> Bool {
    lhs === rhs || (lhs.hash == rhs.hash && lhs.typeID == rhs.typeID && lhs.baseEquals(rhs.payload))
  }

  package func hash(into hasher: inout Hasher) { hasher.combine(hash) }
}

public extension Animation {
  /// The animated value at `time` seconds in, for a change of `value`; nil once the animation has finished.
  func animate<V>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? where V: VectorArithmetic {
    var fractionContext = context.converted(to: Double.self)
    let fraction = _fraction(at: time, change: value.magnitudeSquared.squareRoot(), context: &fractionContext)
    context.state.storage = fractionContext.state.storage
    context.isLogicallyComplete = fractionContext.isLogicallyComplete
    return fraction.map { value.scaled(by: $0) }
  }

  /// The velocity at `time` for a change of `value`: a custom animation's own (nil when it reports none), a built-in
  /// curve's estimated from the curve.
  func velocity<V>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? where V: VectorArithmetic {
    let step = 1.0 / 240
    let distance = value.magnitudeSquared.squareRoot()
    let custom = _customVelocity(at: time, change: distance, context: context.converted(to: Double.self))
    if custom.isCustom {
      guard let rate = custom.rate else { return nil }
      return value.scaled(by: distance > 0 ? rate / distance : 0)
    }
    var early = context.converted(to: Double.self), late = early
    guard let before = _fraction(at: max(time - step, 0), change: distance, context: &early),
          let after = _fraction(at: time + step, change: distance, context: &late) else { return nil }
    return value.scaled(by: (after - before) / (time + step - max(time - step, 0)))
  }

  /// Whether this animation, interrupting `previous`, takes it over: springs do, and a custom animation says so itself.
  func shouldMerge<V>(previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>) -> Bool where V: VectorArithmetic {
    var converted = context.converted(to: Double.self)
    let merges = _shouldMerge(previous: previous, change: value.magnitudeSquared.squareRoot(), time: time, context: &converted)
    context.state.storage = converted.state.storage
    context.isLogicallyComplete = converted.isLogicallyComplete
    return merges
  }
}

public extension VectorArithmetic {
  /// A copy scaled by `rhs`.
  func scaled(by rhs: Double) -> Self {
    var copy = self
    copy.scale(by: rhs)
    return copy
  }

  /// Moves `amount` of the way to `other`.
  mutating func interpolate(towards other: Self, amount: Double) {
    self = self + (other - self).scaled(by: amount)
  }

  /// The value `amount` of the way to `other`.
  func interpolated(towards other: Self, amount: Double) -> Self {
    self + (other - self).scaled(by: amount)
  }
}

public extension Animatable where Self: VectorArithmetic {
  var animatableData: Self {
    get { self }
    set { self = newValue }
  }
}
