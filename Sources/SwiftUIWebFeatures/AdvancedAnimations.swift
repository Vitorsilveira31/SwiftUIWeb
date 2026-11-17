@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// SwiftUI-shaped phase and keyframe animation primitives.
//
// The core deliberately records semantic frames instead of driving a timer
// from Swift. Browser hosts can hand those frames to a native animation
// engine, while static/WASI renderers retain the first frame and all normal
// Fiber identity/state behavior.


public struct UnitCurve: Hashable, Sendable {
  // The CSS spelling of the curve. Hosts read it directly; SwiftUI callers
  // build curves only through the public statics below.
  let rawValue: String
  init(_ rawValue: String) { self.rawValue = rawValue }
  init(rawValue: String) { self.rawValue = rawValue }
  public static let linear = UnitCurve("linear")
  public static let easeIn = UnitCurve("ease-in")
  public static let easeOut = UnitCurve("ease-out")
  public static let easeInOut = UnitCurve("ease-in-out")
  /// The ease-in-out curve: the system's `easeInEaseOut` spelling.
  public static let easeInEaseOut = UnitCurve("ease-in-out")
  /// A quarter of a circle: slow, then fast.
  public static let circularEaseIn = UnitCurve("circular-ease-in")
  /// A quarter of a circle: fast, then slow.
  public static let circularEaseOut = UnitCurve("circular-ease-out")
  /// Two quarters of a circle: slow, fast, then slow.
  public static let circularEaseInOut = UnitCurve("circular-ease-in-out")
  static let `default` = UnitCurve("ease-in-out")

  /// The curve's value at `progress` (0...1).
  public func value(at progress: Double) -> Double {
    let x = min(max(progress, 0), 1)
    switch rawValue {
    case "circular-ease-in": return 1 - _squareRoot(1 - x * x)
    case "circular-ease-out": return _squareRoot(1 - (1 - x) * (1 - x))
    case "circular-ease-in-out":
      return x < 0.5 ? (1 - _squareRoot(1 - 4 * x * x)) / 2 : (_squareRoot(1 - (2 * x - 2) * (2 * x - 2)) + 1) / 2
    case "inverse-circular-ease-in": return _squareRoot(1 - (1 - x) * (1 - x))
    case "inverse-circular-ease-out": return 1 - _squareRoot(1 - x * x)
    case "inverse-circular-ease-in-out":
      return x < 0.5 ? _squareRoot(1 - (1 - 2 * x) * (1 - 2 * x)) / 2 : 1 - _squareRoot(1 - (2 * x - 1) * (2 * x - 1)) / 2
    default:
      let (x1, y1, x2, y2) = bezierPoints
      return _unitBezier(x1, y1, x2, y2, at: x)
    }
  }

  /// The slope of the curve at `progress`.
  public func velocity(at progress: Double) -> Double {
    let step = 1e-4
    let low = max(progress - step, 0), high = min(progress + step, 1)
    return high > low ? (value(at: high) - value(at: low)) / (high - low) : 0
  }

  /// The curve that undoes this one: its value at `y` is the progress at which this one reaches `y`.
  public var inverse: UnitCurve {
    switch rawValue {
    case "circular-ease-in": return UnitCurve("inverse-circular-ease-in")
    case "circular-ease-out": return UnitCurve("inverse-circular-ease-out")
    case "circular-ease-in-out": return UnitCurve("inverse-circular-ease-in-out")
    case "inverse-circular-ease-in": return UnitCurve("circular-ease-in")
    case "inverse-circular-ease-out": return UnitCurve("circular-ease-out")
    case "inverse-circular-ease-in-out": return UnitCurve("circular-ease-in-out")
    default:
      // A Bézier through (0, 0) and (1, 1) is inverted by swapping x and y of its control points.
      let (x1, y1, x2, y2) = bezierPoints
      return UnitCurve.cubicBezier(y1, x1, y2, x2)
    }
  }

  /// The easing published to the browser. CSS spells cubic-bezier curves and keywords directly; the circular curves
  /// have no CSS name, so they are sampled into a `linear(...)` easing (33 evenly spaced progress points).
  var cssEasing: String {
    switch rawValue {
    case "circular-ease-in", "circular-ease-out", "circular-ease-in-out",
      "inverse-circular-ease-in", "inverse-circular-ease-out", "inverse-circular-ease-in-out":
      let steps = 32
      var values: [String] = []
      values.reserveCapacity(steps + 1)
      for index in 0...steps {
        values.append(_cssEasingNumber(value(at: Double(index) / Double(steps))))
      }
      return "linear(" + values.joined(separator: ", ") + ")"
    default:
      return rawValue
    }
  }

  /// The control points of the curve as a Bézier.
  var bezierPoints: (Double, Double, Double, Double) {
    switch rawValue {
    case "linear": return (0, 0, 1, 1)
    case "ease-in": return (0.42, 0, 1, 1)
    case "ease-out": return (0, 0, 0.58, 1)
    case "ease-in-out": return (0.42, 0, 0.58, 1)
    default:
      guard rawValue.hasPrefix("cubic-bezier("), rawValue.hasSuffix(")") else { return (0.42, 0, 0.58, 1) }
      let numbers = rawValue.dropFirst("cubic-bezier(".count).dropLast().split(separator: ",").compactMap { Double(String($0)) }
      return numbers.count == 4 ? (numbers[0], numbers[1], numbers[2], numbers[3]) : (0.42, 0, 0.58, 1)
    }
  }
  public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
    cubicBezier(startControlPoint.x, startControlPoint.y, endControlPoint.x, endControlPoint.y)
  }
  static func cubicBezier(_ c0x: Double, _ c0y: Double, _ c1x: Double, _ c1y: Double) -> UnitCurve {
    UnitCurve("cubic-bezier(\(c0x),\(c0y),\(c1x),\(c1y))")
  }
}

/// Formats a curve value in 0...1 as a CSS number with at most four decimals ("0", "0.0123", "1").
private func _cssEasingNumber(_ value: Double) -> String {
  // NaN passes min and max unchanged and would trap Int().
  let scaled = value.isNaN ? 0 : Int((min(max(value, 0), 1) * 10000).rounded())
  let whole = scaled / 10000
  var fraction = String(scaled % 10000)
  while fraction.count < 4 { fraction = "0" + fraction }
  while fraction.hasSuffix("0") { fraction.removeLast() }
  return fraction.isEmpty ? String(whole) : "\(whole).\(fraction)"
}

/// Renderer vocabulary for one semantic keyframe segment; not SwiftUI API.
@_spi(Renderer) public enum KeyframeSegmentKind: String, Hashable, Sendable {
  case linear
  case cubic
  case spring
  case move
}

/// A compact SwiftUI-shaped spring descriptor used by `SpringKeyframe`.
/// Browsers receive the resulting semantic frame sequence; the descriptor
/// remains available to native/WASI hosts and custom renderers as value data.
public struct Spring: Hashable, Sendable {
  public let duration: Double
  public let bounce: Double

  public init(duration: TimeInterval = 0.5, bounce: Double = 0) {
    self.duration = max(0, duration)
    self.bounce = min(max(bounce, -1), 1)
  }

  public init(mass: Double = 1, stiffness: Double, damping: Double, allowOverDamping: Bool = false) {
    let response = 2 * Double.pi * (max(0.01, mass) / max(0.01, stiffness)).squareRoot()
    let fraction = max(0, damping) / (2 * (max(0.01, mass) * max(0.01, stiffness)).squareRoot())
    // An overdamped spring is kept only when asked for: otherwise it is critically damped, as in SwiftUI. An underdamped one
    // bounces either way.
    let bounce = Spring._bounce(dampingRatio: fraction)
    self.init(duration: max(0.12, response), bounce: allowOverDamping ? bounce : max(0, bounce))
  }

  public init(response: Double, dampingRatio: Double) {
    self.init(duration: max(0.01, response), bounce: Spring._bounce(dampingRatio: dampingRatio))
  }

  public init(settlingDuration: TimeInterval, dampingRatio: Double, epsilon: Double = 0.001) {
    _ = epsilon
    self.init(duration: max(0, settlingDuration), bounce: Spring._bounce(dampingRatio: dampingRatio))
  }

  /// The bounce of a damping ratio, the inverse of how a bounce becomes a ratio (`_SpringMotion.init(duration:bounce:)`): one
  /// less the ratio up to critical damping, and `1 / ratio - 1` beyond it, so that a ratio of 2 plays as a ratio of 2.
  static func _bounce(dampingRatio: Double) -> Double {
    guard dampingRatio.isFinite else { return dampingRatio > 0 ? -1 : 1 }
    let ratio = max(0, dampingRatio)
    return ratio <= 1 ? 1 - ratio : max(-1, 1 / ratio - 1)
  }

  static let `default` = Spring()
  public static let smooth = Spring(duration: 0.5, bounce: 0)
  public static let snappy = Spring(duration: 0.5, bounce: 0.15)
  public static let bouncy = Spring(duration: 0.5, bounce: 0.3)
}

/// A single semantic keyframe. The value is retained by the Swift renderer
/// for timeline queries; `valueDescription` is the backend-neutral form used
/// when a browser host serializes the animation without exposing JavaScript.
@_spi(Renderer) public struct KeyframeSegment {
  public let kind: KeyframeSegmentKind
  public let duration: Double
  public let valueDescription: String
  public let timingCurve: UnitCurve
  fileprivate let value: _RuntimeValue
  fileprivate let numericValue: Double?
  /// A cubic keyframe's velocities, in units per second (nil: from the neighboring keyframes).
  fileprivate var startVelocity: Double? = nil
  fileprivate var endVelocity: Double? = nil
  /// A spring keyframe's spring.
  fileprivate var spring: _SpringMotion? = nil

  fileprivate init<Value>(kind: KeyframeSegmentKind, value: Value, duration: Double, timingCurve: UnitCurve) {
    self.kind = kind
    self.duration = max(0, duration)
    self.value = _RuntimeValue(value)
    self.valueDescription = _swiftUIWebDescribe(value)
    self.numericValue = _keyframeNumericValue(_RuntimeValue(value))
    self.timingCurve = timingCurve
  }
}

/// SwiftUI's keyframe content protocol. The semantic segments are the
/// renderer's view of a value; they are SPI.
public protocol KeyframeTrackContent<Value> {
  associatedtype Value
  associatedtype Body: KeyframeTrackContent
  @KeyframeTrackContentBuilder<Value> var body: Body { get }
  @_spi(Renderer) var _swiftUIWebKeyframeSegments: [KeyframeSegment] { get }
}

public extension KeyframeTrackContent {
  @_spi(Renderer) var _swiftUIWebKeyframeSegments: [KeyframeSegment] { body._swiftUIWebKeyframeSegments }
}

public struct LinearKeyframe<Value>: KeyframeTrackContent {
  public typealias Body = LinearKeyframe<Value>
  let value: Value
  let duration: TimeInterval
  let timingCurve: UnitCurve

  public init(_ value: Value, duration: TimeInterval, timingCurve: UnitCurve = .linear) {
    self.value = value
    self.duration = duration
    self.timingCurve = timingCurve
  }

  @_spi(Renderer) public var body: LinearKeyframe<Value> { self }

  @_spi(Renderer) public var _swiftUIWebKeyframeSegments: [KeyframeSegment] {
    [KeyframeSegment(kind: .linear, value: value, duration: duration, timingCurve: timingCurve)]
  }
}

public struct CubicKeyframe<Value>: KeyframeTrackContent {
  public typealias Body = CubicKeyframe<Value>
  let value: Value
  let duration: TimeInterval
  let timingCurve: UnitCurve
  let startVelocity: Value?
  let endVelocity: Value?

  /// SwiftUI's cubic keyframe initializer. Velocity values are retained for
  /// custom hosts; the compact browser backend uses the same cubic semantic
  /// segment and lets CSS/WAAPI perform interpolation.
  public init(_ value: Value, duration: TimeInterval, startVelocity: Value? = nil, endVelocity: Value? = nil) {
    self.value = value
    self.duration = duration
    self.timingCurve = .easeInOut
    self.startVelocity = startVelocity
    self.endVelocity = endVelocity
  }

  @_spi(Renderer) public var body: CubicKeyframe<Value> { self }

  @_spi(Renderer) public var _swiftUIWebKeyframeSegments: [KeyframeSegment] {
    var segment = KeyframeSegment(kind: .cubic, value: value, duration: duration, timingCurve: timingCurve)
    segment.startVelocity = startVelocity.flatMap { _keyframeNumericValue(_RuntimeValue($0)) }
    segment.endVelocity = endVelocity.flatMap { _keyframeNumericValue(_RuntimeValue($0)) }
    return [segment]
  }
}

public struct SpringKeyframe<Value>: KeyframeTrackContent {
  public typealias Body = SpringKeyframe<Value>
  let value: Value
  let duration: TimeInterval?
  let spring: Spring
  let startVelocity: Value?

  public init(_ value: Value, duration: TimeInterval? = nil, spring: Spring = Spring(), startVelocity: Value? = nil) {
    self.value = value
    self.duration = duration
    self.spring = spring
    self.startVelocity = startVelocity
  }

  @_spi(Renderer) public var body: SpringKeyframe<Value> { self }

  @_spi(Renderer) public var _swiftUIWebKeyframeSegments: [KeyframeSegment] {
    // Without a duration the keyframe lasts until the spring settles, as in SwiftUI; with one, the spring's curve is
    // played over it.
    let motion = _SpringMotion(duration: spring.duration, bounce: spring.bounce)
    let played = duration ?? motion.settlingDuration()
    var segment = KeyframeSegment(kind: .spring, value: value, duration: played, timingCurve: UnitCurve(motion.cssEasing(duration: played)))
    segment.spring = motion
    segment.startVelocity = startVelocity.flatMap { _keyframeNumericValue(_RuntimeValue($0)) }
    return [segment]
  }
}

public struct MoveKeyframe<Value>: KeyframeTrackContent {
  public typealias Body = MoveKeyframe<Value>
  let value: Value
  let duration: TimeInterval

  public init(_ value: Value) {
    self.init(value, duration: 0)
  }

  init(_ value: Value, duration: TimeInterval) {
    self.value = value
    self.duration = duration
  }

  @_spi(Renderer) public var body: MoveKeyframe<Value> { self }

  @_spi(Renderer) public var _swiftUIWebKeyframeSegments: [KeyframeSegment] {
    [KeyframeSegment(kind: .move, value: value, duration: duration, timingCurve: .linear)]
  }
}

/// The segments of a built keyframe body. Builders return it (as an opaque
/// `KeyframeTrackContent`) whenever several pieces are combined.
@_spi(Renderer) public struct _KeyframeSegments<Value>: KeyframeTrackContent {
  public typealias Body = _KeyframeSegments<Value>
  public let _swiftUIWebKeyframeSegments: [KeyframeSegment]

  init(_ segments: [KeyframeSegment]) { self._swiftUIWebKeyframeSegments = segments }

  public var body: _KeyframeSegments<Value> { self }
}

@resultBuilder
public struct KeyframeTrackContentBuilder<Value> {
  public static func buildExpression<K: KeyframeTrackContent>(_ expression: K) -> K where K.Value == Value {
    expression
  }
  public static func buildBlock() -> some KeyframeTrackContent<Value> {
    _KeyframeSegments<Value>([])
  }
  public static func buildPartialBlock<K: KeyframeTrackContent>(first: K) -> K where K.Value == Value {
    first
  }
  public static func buildPartialBlock(
    accumulated: some KeyframeTrackContent<Value>,
    next: some KeyframeTrackContent<Value>
  ) -> some KeyframeTrackContent<Value> {
    _KeyframeSegments<Value>(accumulated._swiftUIWebKeyframeSegments + next._swiftUIWebKeyframeSegments)
  }
  // Both branches must produce one concrete type so `if`/`else` unifies; the
  // builder's result is therefore the SPI segment list rather than an opaque type.
  @_spi(Renderer) public static func buildEither<First: KeyframeTrackContent>(first component: First) -> _KeyframeSegments<Value> where First.Value == Value {
    _KeyframeSegments<Value>(component._swiftUIWebKeyframeSegments)
  }
  @_spi(Renderer) public static func buildEither<Second: KeyframeTrackContent>(second component: Second) -> _KeyframeSegments<Value> where Second.Value == Value {
    _KeyframeSegments<Value>(component._swiftUIWebKeyframeSegments)
  }
  public static func buildArray(_ components: [some KeyframeTrackContent<Value>]) -> some KeyframeTrackContent<Value> {
    _KeyframeSegments<Value>(components.flatMap { $0._swiftUIWebKeyframeSegments })
  }
}

/// Renderer vocabulary for one keyframe track: its segments and, when the
/// track targets a property, how to write a sampled value back. Not SwiftUI API.
@_spi(Renderer) public struct KeyframeTrackDescriptor {
  public let keyPath: String?
  public let segments: [KeyframeSegment]
  fileprivate let apply: ((_RuntimeValue, Double, Double) -> _RuntimeValue)?

  public init(keyPath: String? = nil, segments: [KeyframeSegment]) {
    self.keyPath = keyPath
    self.segments = segments
    self.apply = nil
  }

  fileprivate init(keyPath: String?, segments: [KeyframeSegment], apply: ((_RuntimeValue, Double, Double) -> _RuntimeValue)?) {
    self.keyPath = keyPath
    self.segments = segments
    self.apply = apply
  }
}

/// SwiftUI's keyframe-timeline protocol. Its `Value` is the value the timeline
/// animates, which conformers relate to their tracks through the track
/// descriptors (SPI). The descriptor requirement takes the initial value so a
/// primitive track's `Value` is inferred from its root type, as in SwiftUI.
public protocol Keyframes<Value> {
  associatedtype Value
  associatedtype Body: Keyframes
  @KeyframesBuilder<Self.Value> var body: Body { get }
  @_spi(Renderer) func _swiftUIWebKeyframeTracks(initialValue: Self.Value?) -> [KeyframeTrackDescriptor]
}

public extension Keyframes where Value == Body.Value {
  @_spi(Renderer) func _swiftUIWebKeyframeTracks(initialValue: Value?) -> [KeyframeTrackDescriptor] {
    body._swiftUIWebKeyframeTracks(initialValue: initialValue)
  }
}

/// Primitive keyframe tracks have `Body == Never` and provide their tracks directly.
public extension Keyframes where Body == Never {
  var body: Never { fatalError("A primitive keyframe track has no body") }
}

// `Never`'s `Value` and `body` come from its `Gesture` conformance, which has
// the same shape, so this conformance adds nothing else.
extension Never: Keyframes {}

/// The track list a builder returns for several keyframes.
@_spi(Renderer) public struct _KeyframeTrackList<Value>: Keyframes {
  public typealias Body = _KeyframeTrackList<Value>
  private let tracks: [KeyframeTrackDescriptor]

  init(_ tracks: [KeyframeTrackDescriptor]) { self.tracks = tracks }

  public func _swiftUIWebKeyframeTracks(initialValue: Value?) -> [KeyframeTrackDescriptor] { tracks }

  public var body: _KeyframeTrackList<Value> { self }
}

public struct KeyframeTrack<Root, Value, Content>: Keyframes where Value == Content.Value, Content: KeyframeTrackContent {
  public typealias Body = Never
  let keyPath: WritableKeyPath<Root, Value>?
  let content: Content
  private let embeddedMember: String?
  private let embeddedGet: ((Root) -> Value)?
  private let embeddedSet: ((inout Root, Value) -> Void)?

  public init(
    _ keyPath: WritableKeyPath<Root, Value>,
    @KeyframeTrackContentBuilder<Value> content: () -> Content
  ) {
    self.keyPath = keyPath
    self.content = content()
    self.embeddedMember = nil
    embeddedGet = nil; embeddedSet = nil
  }

  #if hasFeature(Embedded)
  /// Lowering target for `KeyframeTrack(\.member)`. Embedded Swift cannot
  /// materialize WritableKeyPath, while the browser renderer only needs the
  /// stable member label plus the semantic segment timeline.
  public init(
    _embeddedMember member: String,
    _embeddedGet get: @escaping (Root) -> Value,
    _embeddedSet set: @escaping (inout Root, Value) -> Void,
    @KeyframeTrackContentBuilder<Value> content: () -> Content
  ) {
    self.keyPath = nil
    self.content = content()
    self.embeddedMember = member
    embeddedGet = get; embeddedSet = set
  }
  #endif

  public init(@KeyframeTrackContentBuilder<Root> content: () -> Content) where Root == Content.Value {
    keyPath = nil
    self.content = content()
    self.embeddedMember = nil
    embeddedGet = nil; embeddedSet = nil
  }

  @_spi(Renderer) public func _swiftUIWebKeyframeTracks(initialValue: Root?) -> [KeyframeTrackDescriptor] {
    let segments = content._swiftUIWebKeyframeSegments
    #if hasFeature(Embedded)
    if let get = embeddedGet, let set = embeddedSet {
      return [KeyframeTrackDescriptor(keyPath: embeddedMember, segments: segments, apply: { raw, progress, duration in
        guard var root: Root = raw.read(),
              let sample = _keyframeTimelineValue(segments, progress: progress, timelineDuration: duration, current: _RuntimeValue(get(root))),
              let value: Value = sample.read() else { return raw }
        set(&root, value)
        return _RuntimeValue(root)
      })]
    }
    #else
    if let keyPath {
      return [KeyframeTrackDescriptor(keyPath: "keyPath", segments: segments, apply: { raw, progress, duration in
        guard var root: Root = raw.read(),
              let sample = _keyframeTimelineValue(segments, progress: progress, timelineDuration: duration, current: _RuntimeValue(root[keyPath: keyPath])),
              let value: Value = sample.read() else { return raw }
        root[keyPath: keyPath] = value
        return _RuntimeValue(root)
      })]
    }
    #endif
    return [KeyframeTrackDescriptor(keyPath: nil, segments: segments, apply: { raw, progress, duration in
      _keyframeTimelineValue(segments, progress: progress, timelineDuration: duration, current: raw) ?? raw
    })]
  }
}

/// SwiftUI's keyframes builder. Its statements are either whole `Keyframes`
/// (tracks such as `KeyframeTrack`) or `KeyframeTrackContent` pieces. Loose
/// pieces form one track, which `buildFinalResult` wraps in a `KeyframeTrack`.
@resultBuilder
public struct KeyframesBuilder<Value> {
  public static func buildExpression<K: KeyframeTrackContent>(_ expression: K) -> K where K.Value == Value {
    expression
  }
  public static func buildArray(_ components: [some KeyframeTrackContent<Value>]) -> some KeyframeTrackContent<Value> {
    _KeyframeSegments<Value>(components.flatMap { $0._swiftUIWebKeyframeSegments })
  }
  @_spi(Renderer) public static func buildEither<First: KeyframeTrackContent>(first component: First) -> _KeyframeSegments<Value> where First.Value == Value {
    _KeyframeSegments<Value>(component._swiftUIWebKeyframeSegments)
  }
  @_spi(Renderer) public static func buildEither<Second: KeyframeTrackContent>(second component: Second) -> _KeyframeSegments<Value> where Second.Value == Value {
    _KeyframeSegments<Value>(component._swiftUIWebKeyframeSegments)
  }
  public static func buildPartialBlock<K: KeyframeTrackContent>(first: K) -> K where K.Value == Value {
    first
  }
  public static func buildPartialBlock(
    accumulated: some KeyframeTrackContent<Value>,
    next: some KeyframeTrackContent<Value>
  ) -> some KeyframeTrackContent<Value> {
    _KeyframeSegments<Value>(accumulated._swiftUIWebKeyframeSegments + next._swiftUIWebKeyframeSegments)
  }
  public static func buildBlock() -> some KeyframeTrackContent<Value> where Value: Animatable {
    _KeyframeSegments<Value>([])
  }
  public static func buildFinalResult<Content: KeyframeTrackContent>(_ component: Content) -> KeyframeTrack<Value, Value, Content> where Content.Value == Value {
    KeyframeTrack(content: { component })
  }

  public static func buildExpression<Content: Keyframes>(_ expression: Content) -> Content where Content.Value == Value {
    expression
  }
  public static func buildPartialBlock<Content: Keyframes>(first: Content) -> Content where Content.Value == Value {
    first
  }
  public static func buildPartialBlock(
    accumulated: some Keyframes<Value>,
    next: some Keyframes<Value>
  ) -> some Keyframes<Value> {
    _KeyframeTrackList<Value>(
      accumulated._swiftUIWebKeyframeTracks(initialValue: nil) + next._swiftUIWebKeyframeTracks(initialValue: nil)
    )
  }
  public static func buildBlock() -> some Keyframes<Value> {
    _KeyframeTrackList<Value>([])
  }
  public static func buildFinalResult<Content: Keyframes>(_ component: Content) -> Content where Content.Value == Value {
    component
  }
}

public struct KeyframeTimeline<Value> {
  private let initialValue: Value
  let tracks: [KeyframeTrackDescriptor]
  public let duration: TimeInterval

  public init(
    initialValue: Value,
    @KeyframesBuilder<Value> content: () -> some Keyframes<Value>
  ) {
    self.init(initialValue: initialValue, tracks: content()._swiftUIWebKeyframeTracks(initialValue: initialValue))
  }

  init(initialValue: Value, tracks: [KeyframeTrackDescriptor]) {
    self.initialValue = initialValue
    self.tracks = tracks
    duration = tracks.map { $0.segments.reduce(0) { $0 + max(0, $1.duration) } }.max() ?? 0
  }

  public func value(time: Double) -> Value {
    value(progress: duration > 0 ? time / duration : 1)
  }

  public func value(progress: Double) -> Value {
    let progress = min(1, max(0, progress))
    var result = _RuntimeValue(initialValue)
    for track in tracks {
      if let apply = track.apply { result = apply(result, progress, duration) }
    }
    return result.read(Value.self) ?? initialValue
  }
}

/// A view container matching SwiftUI's `PhaseAnimator` initializer family.
/// The browser host consumes frame metadata; static hosts render the initial
/// phase while retaining the same child identity and state.
public nonisolated struct PhaseAnimator<Phase: Equatable, Content: View>: View {
  public typealias Body = Never
  private let phases: [Phase]
  private let triggerGeneration: _TriggerGeneration?
  private let content: (Phase) -> Content
  private let animation: (Phase) -> Animation?

  public nonisolated init(
    _ phases: some Sequence<Phase>,
    @ViewBuilder content: @escaping (Phase) -> Content,
    animation: @escaping (Phase) -> Animation? = { _ in .default }
  ) {
    self.phases = Array(phases)
    triggerGeneration = nil
    self.content = content
    self.animation = animation
  }

  public nonisolated init(
    _ phases: some Sequence<Phase>,
    trigger: some Equatable,
    @ViewBuilder content: @escaping (Phase) -> Content,
    animation: @escaping (Phase) -> Animation? = { _ in .default }
  ) {
    self.phases = Array(phases)
    nonisolated(unsafe) let trigger = trigger
    triggerGeneration = { store, key in store._identityGeneration(key: key, value: trigger) }
    self.content = content
    self.animation = animation
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    guard !phases.isEmpty else {
      let node = _RenderNode.element("span")
      node.attributes["data-phase-animator-error"] = "empty"
      node.children = [.text("PhaseAnimator requires at least one phase")]
      return node
    }
    let frames = phases.enumerated().map { index, phase in
      content(phase)._render(in: _animatorSampleContext(context.child(_FiberKey("phase-\(index)")), mounted: index == 0))
    }
    let node = frames[0]
    _applyPhaseAnimationMetadata(
      to: node,
      phases: phases,
      frames: frames,
      triggerDescription: _triggerToken(triggerGeneration, key: context._compactPathID + "#phase-trigger", context: context),
      animations: phases.map(animation)
    )
    return node
  }
}

/// A SwiftUI-shaped `KeyframeAnimator` container. Like the modifier form,
/// this container evaluates its content only for semantic timeline snapshots;
/// browser hosts interpolate those snapshots natively and static hosts keep
/// the initial value deterministic.
public nonisolated struct KeyframeAnimator<Value, KeyframePath, Content>: View where Value == KeyframePath.Value, KeyframePath: Keyframes, Content: View {
  public typealias Body = Never
  private let initialValue: Value
  private let triggerGeneration: _TriggerGeneration?
  private let repeating: Bool
  private let content: (Value) -> Content
  private let keyframes: (Value) -> KeyframePath

  public nonisolated init(
    initialValue: Value,
    repeating: Bool = true,
    @ViewBuilder content: @escaping (Value) -> Content,
    @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath
  ) {
    self.initialValue = initialValue
    triggerGeneration = nil
    self.repeating = repeating
    self.content = content
    self.keyframes = keyframes
  }

  public nonisolated init(
    initialValue: Value,
    trigger: some Equatable,
    @ViewBuilder content: @escaping (Value) -> Content,
    @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath
  ) {
    self.initialValue = initialValue
    nonisolated(unsafe) let trigger = trigger
    triggerGeneration = { store, key in store._identityGeneration(key: key, value: trigger) }
    repeating = false
    self.content = content
    self.keyframes = keyframes
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let tracks = keyframes(initialValue)._swiftUIWebKeyframeTracks(initialValue: initialValue)
    let timeline = KeyframeTimeline(initialValue: initialValue, tracks: tracks)
    let progresses = _keyframeFrameProgresses(tracks, duration: timeline.duration)
    let frames = progresses.enumerated().map { index, progress in
      // Snapshots are not mounted subtrees. Reuse one semantic path while
      // evaluating them so stateful content does not allocate one State box
      // per sample; only the first snapshot becomes the mounted Fiber node.
      content(timeline.value(progress: progress))._render(in: _animatorSampleContext(context.child(_FiberKey("keyframe")), mounted: index == 0))
    }
    guard let node = frames.first else { return _RenderNode.empty() }
    node.attributes["data-keyframe-animator"] = "true"
    node.attributes["data-keyframe-repeating"] = repeating ? "true" : "false"
    node.attributes["data-keyframe-trigger"] = _triggerToken(triggerGeneration, key: context._compactPathID + "#keyframe-trigger", context: context) ?? ""
    node.attributes["data-keyframe-duration"] = _animationNumber(timeline.duration)
    node.attributes["data-keyframe-tracks"] = _encodeKeyframeTracks(tracks)
    node.attributes["data-keyframe-offsets"] = progresses.map(_animationNumber).joined(separator: ",")
    node.attributes["data-keyframe-easings"] = _keyframeFrameEasings(tracks, progresses: progresses, duration: timeline.duration).map(_animationEscaped).joined(separator: ",")
    node.attributes["data-keyframe-frames"] = frames.map { _animationStyleSnapshot($0) }.joined(separator: "|")
    return node
  }
}

public nonisolated struct _PhaseAnimatorModifier<Phase: Equatable, Trigger: Equatable>: ViewModifier {
  public typealias Body = AnyView
  private let phases: [Phase]
  private let trigger: Trigger?
  private let baseView: AnyView
  private let content: (AnyView, Phase) -> AnyView
  private let animation: (Phase) -> Animation?

  init(
    phases: [Phase],
    trigger: Trigger?,
    baseView: AnyView,
    content: @escaping (AnyView, Phase) -> AnyView,
    animation: @escaping (Phase) -> Animation?
  ) {
    self.phases = phases
    self.trigger = trigger
    self.baseView = baseView
    self.content = content
    self.animation = animation
  }

  @MainActor public func body(content base: Content) -> AnyView {
    guard let first = phases.first else { return AnyView(base) }
    return AnyView(content(AnyView(base), first))
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard !phases.isEmpty else {
      node.attributes["data-phase-animator-error"] = "empty"
      return
    }
    let frames = phases.enumerated().map { index, phase in
      content(AnyView(EmptyView()), phase)._render(in: _animatorSampleContext(context.child(_FiberKey("phase-\(index)")), mounted: false))
    }
    let baseline = baseView._render(in: context)
    let styleFrames = frames.map { _animationStyleSnapshot($0, inherited: baseline.styles) }
    _applyPhaseAnimationMetadata(
      to: node,
      phases: phases,
      frames: frames,
      triggerDescription: _triggerToken(trigger, key: context._modifierStateKey("#phase-trigger"), context: context),
      animations: phases.map(animation),
      styleFrames: styleFrames
    )
  }
}

public nonisolated struct _KeyframeAnimatorModifier<Value, Trigger: Equatable>: ViewModifier {
  public typealias Body = AnyView
  private let initialValue: Value
  private let trigger: Trigger?
  private let repeating: Bool
  private let baseView: AnyView
  private let content: (AnyView, Value) -> AnyView
  private let keyframes: (Value) -> [KeyframeTrackDescriptor]

  init(
    initialValue: Value,
    trigger: Trigger?,
    repeating: Bool,
    baseView: AnyView,
    content: @escaping (AnyView, Value) -> AnyView,
    keyframes: @escaping (Value) -> [KeyframeTrackDescriptor]
  ) {
    self.initialValue = initialValue
    self.trigger = trigger
    self.repeating = repeating
    self.baseView = baseView
    self.content = content
    self.keyframes = keyframes
  }

  @MainActor public func body(content base: Content) -> AnyView {
    AnyView(content(AnyView(base), initialValue))
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let tracks = keyframes(initialValue)
    let timeline = KeyframeTimeline(initialValue: initialValue, tracks: tracks)
    let progresses = _keyframeFrameProgresses(tracks, duration: timeline.duration)
    var frames: [_RenderNode] = []
    frames.reserveCapacity(progresses.count)
    for progress in progresses {
      // The empty placeholder means these are style-only snapshots. Keep a
      // shared path to avoid registering discarded sample content as distinct
      // stateful children.
      frames.append(content(AnyView(EmptyView()), timeline.value(progress: progress))._render(in: _animatorSampleContext(context.child(_FiberKey("keyframe")), mounted: false)))
    }
    let baseline = baseView._render(in: context)
    let styleFrames = frames.map { _animationStyleSnapshot($0, inherited: baseline.styles) }
    node.attributes["data-keyframe-animator"] = "true"
    node.attributes["data-keyframe-repeating"] = repeating ? "true" : "false"
    node.attributes["data-keyframe-trigger"] = _triggerToken(trigger, key: context._modifierStateKey("#keyframe-trigger"), context: context) ?? ""
    node.attributes["data-keyframe-duration"] = _animationNumber(timeline.duration)
    node.attributes["data-keyframe-tracks"] = _encodeKeyframeTracks(tracks)
    node.attributes["data-keyframe-offsets"] = progresses.map(_animationNumber).joined(separator: ",")
    node.attributes["data-keyframe-easings"] = _keyframeFrameEasings(tracks, progresses: progresses, duration: timeline.duration).map(_animationEscaped).joined(separator: ",")
    node.attributes["data-keyframe-frames"] = styleFrames.joined(separator: "|")
  }
}

public extension View {
  nonisolated func phaseAnimator<Phase: Equatable>(
    _ phases: some Sequence<Phase>,
    @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> some View,
    animation: @escaping (Phase) -> Animation? = { _ in .default }
  ) -> some View {
    ModifiedContent(content: self, modifier: _PhaseAnimatorModifier(
      phases: Array(phases), trigger: nil as Bool?, baseView: AnyView(self),
      content: { base, phase in AnyView(content(PlaceholderContentView(base), phase)) }, animation: animation
    ))
  }

  nonisolated func phaseAnimator<Phase: Equatable>(
    _ phases: some Sequence<Phase>,
    trigger: some Equatable,
    @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> some View,
    animation: @escaping (Phase) -> Animation? = { _ in .default }
  ) -> some View {
    ModifiedContent(content: self, modifier: _PhaseAnimatorModifier(
      phases: Array(phases), trigger: trigger, baseView: AnyView(self),
      content: { base, phase in AnyView(content(PlaceholderContentView(base), phase)) }, animation: animation
    ))
  }

  nonisolated func keyframeAnimator<Value>(
    initialValue: Value,
    trigger: some Equatable,
    @ViewBuilder content: @escaping @Sendable (PlaceholderContentView<Self>, Value) -> some View,
    @KeyframesBuilder<Value> keyframes: @escaping (Value) -> some Keyframes<Value>
  ) -> some View {
    ModifiedContent(content: self, modifier: _KeyframeAnimatorModifier(
      initialValue: initialValue, trigger: trigger, repeating: false, baseView: AnyView(self),
      content: { base, value in AnyView(content(PlaceholderContentView(base), value)) },
      keyframes: { keyframes($0)._swiftUIWebKeyframeTracks(initialValue: $0) }
    ))
  }

  nonisolated func keyframeAnimator<Value>(
    initialValue: Value,
    repeating: Bool = true,
    @ViewBuilder content: @escaping @Sendable (PlaceholderContentView<Self>, Value) -> some View,
    @KeyframesBuilder<Value> keyframes: @escaping (Value) -> some Keyframes<Value>
  ) -> some View {
    ModifiedContent(content: self, modifier: _KeyframeAnimatorModifier(
      initialValue: initialValue, trigger: nil as Bool?, repeating: repeating, baseView: AnyView(self),
      content: { base, value in AnyView(content(PlaceholderContentView(base), value)) },
      keyframes: { keyframes($0)._swiftUIWebKeyframeTracks(initialValue: $0) }
    ))
  }
}

private func _keyframeNumericValue(_ value: _RuntimeValue) -> Double? {
  if let value = value.read(Double.self) { return value }
  if let value = value.read(Float.self) { return Double(value) }
  if let value = value.read(CGFloat.self) { return Double(value) }
  if let value = value.read(Int.self) { return Double(value) }
  if let value = value.read(Int8.self) { return Double(value) }
  if let value = value.read(Int16.self) { return Double(value) }
  if let value = value.read(Int32.self) { return Double(value) }
  if let value = value.read(Int64.self) { return Double(value) }
  if let value = value.read(UInt.self) { return Double(value) }
  if let value = value.read(Angle.self) { return value.radians }
  return nil
}

/// Returns the semantic sample points needed to preserve segment timing in a
/// browser keyframe timeline. Segment boundaries are normalized against the
/// longest track (the timeline duration), so shorter tracks reach their final
/// value and hold it while longer tracks continue.
private func _keyframeFrameProgresses(_ tracks: [KeyframeTrackDescriptor], duration: Double) -> [Double] {
  guard duration > 0 else { return [0, 1] }
  var points: Set<Double> = [0, 1]
  // Swift evaluates every track's curve (springs, cubic splines, timing curves), so the samples are close enough for
  // the page to join them with straight lines: 60 a second, at most 120, besides the times of the keyframes.
  let count = min(max(Int(min(duration * 60, 120)), 2), 120)
  for index in 1..<count { points.insert(Double(index) / Double(count)) }
  for track in tracks {
    let trackDuration = track.segments.reduce(0) { $0 + max(0, $1.duration) }
    guard trackDuration > 0 else { continue }
    var elapsed = 0.0
    for segment in track.segments {
      elapsed += max(0, segment.duration)
      points.insert(min(1, max(0, elapsed / duration)))
    }
  }
  return points.sorted()
}

/// Chooses the timing curve for each interval between serialized samples.
/// WAAPI allows an easing per keyframe; when several tracks overlap, the
/// first track that owns the interval provides the curve and the remaining
/// tracks continue to interpolate at the same sample offsets.
private func _keyframeFrameEasings(
  _ tracks: [KeyframeTrackDescriptor],
  progresses: [Double],
  duration: Double
) -> [String] {
  guard progresses.count > 1 else { return [] }
  // The samples carry the curves (see `_keyframeFrameProgresses`): the page joins them linearly.
  if progresses.count > 2 { return progresses.dropLast().map { _ in UnitCurve.linear.rawValue } }
  return progresses.dropLast().map { progress in
    let absoluteTime = min(duration, max(0, progress) * duration)
    for track in tracks {
      var elapsed = 0.0
      for segment in track.segments {
        let end = elapsed + max(0, segment.duration)
        if absoluteTime < end || end == elapsed {
          return segment.timingCurve.cssEasing
        }
        elapsed = end
      }
    }
    return UnitCurve.linear.rawValue
  }
}

private func _keyframeTimelineValue(
  _ segments: [KeyframeSegment],
  progress: Double,
  timelineDuration: Double,
  current: _RuntimeValue? = nil
) -> _RuntimeValue? {
  guard !segments.isEmpty else { return current }
  let total = segments.reduce(0) { $0 + max(0, $1.duration) }
  let targetTime = min(total, min(1, max(0, progress)) * max(total, timelineDuration))
  var elapsed = 0.0
  var previous = current
  // The value each keyframe starts from, for the velocities of cubic keyframes that leave them to their neighbors.
  var starts: [Double?] = []
  var running = current.flatMap(_keyframeNumericValue)
  for segment in segments { starts.append(running); running = segment.kind == .move ? segment.numericValue : (segment.numericValue ?? running) }
  for (index, segment) in segments.enumerated() {
    let duration = max(0, segment.duration)
    let end = elapsed + duration
    let local: Double
    if duration == 0 { local = targetTime >= elapsed ? 1 : 0 }
    else { local = min(1, max(0, (targetTime - elapsed) / duration)) }
    if segment.kind == .move {
      if targetTime >= elapsed { previous = segment.value }
    } else if let prior = previous, let from = _keyframeNumericValue(prior), let to = segment.numericValue {
      let value: Double
      switch segment.kind {
      case .spring:
        let motion = segment.spring ?? _SpringMotion(duration: 0.5, bounce: 0)
        let change = to - from
        let velocity = change != 0 ? (segment.startVelocity ?? 0) / change : 0
        let spring = _SpringMotion(response: motion.response, dampingRatio: motion.dampingRatio, initialVelocity: velocity)
        value = from + change * (local >= 1 ? 1 : spring.value(at: local * duration))
      case .cubic:
        // A Hermite spline: each keyframe's velocity is given, or that of the line through its neighbors.
        let previousStart = index > 0 ? starts[index - 1] : nil
        let previousDuration = index > 0 ? max(0, segments[index - 1].duration) : 0
        let next = index + 1 < segments.count ? segments[index + 1] : nil
        let startSlope = segment.startVelocity ?? (previousStart.map { (to - $0) / max(previousDuration + duration, 1e-9) } ?? 0)
        let endSlope = segment.endVelocity ?? (next.flatMap { neighbor in neighbor.numericValue.map { ($0 - from) / max(duration + max(0, neighbor.duration), 1e-9) } } ?? 0)
        let t = local, t2 = t * t, t3 = t2 * t
        value = (2 * t3 - 3 * t2 + 1) * from + (t3 - 2 * t2 + t) * duration * startSlope + (-2 * t3 + 3 * t2) * to + (t3 - t2) * duration * endSlope
      default:
        value = from + (to - from) * segment.timingCurve.value(at: local)
      }
      previous = _keyframeConvertNumeric(value, to: segment.value, fallback: segment.value)
    } else if targetTime >= end {
      previous = segment.value
    }
    if targetTime <= end { return previous }
    elapsed = end
  }
  return previous ?? segments.last?.value
}

private func _keyframeConvertNumeric(_ value: Double, to target: _RuntimeValue, fallback: _RuntimeValue) -> _RuntimeValue {
  guard value.isFinite else { return fallback }
  if target.read(Double.self) != nil { return _RuntimeValue(value) }
  if target.read(Float.self) != nil { return _RuntimeValue(Float(value)) }
  if target.read(CGFloat.self) != nil { return _RuntimeValue(CGFloat(value)) }
  if target.read(Angle.self) != nil { return _RuntimeValue(Angle(radians: value)) }
  if target.read(Int.self) != nil, let converted = Int(exactly: value.rounded()) { return _RuntimeValue(converted) }
  if target.read(Int8.self) != nil, let converted = Int8(exactly: value.rounded()) { return _RuntimeValue(converted) }
  if target.read(Int16.self) != nil, let converted = Int16(exactly: value.rounded()) { return _RuntimeValue(converted) }
  if target.read(Int32.self) != nil, let converted = Int32(exactly: value.rounded()) { return _RuntimeValue(converted) }
  if target.read(Int64.self) != nil, let converted = Int64(exactly: value.rounded()) { return _RuntimeValue(converted) }
  if target.read(UInt.self) != nil, let converted = UInt(exactly: value.rounded()) { return _RuntimeValue(converted) }
  return fallback
}

private func _animationNumber(_ value: Double) -> String {
  guard value.isFinite else { return "0" }
  if let integer = Int(exactly: value) { return String(integer) }
  return String(value)
}

private func _animationEscaped(_ value: String) -> String {
  var result = ""
  result.reserveCapacity(value.utf8.count)
  for scalar in value.unicodeScalars {
    switch scalar.value {
    case 37: result += "%25" // %
    case 124: result += "%7C" // |
    case 59: result += "%3B" // ;
    case 61: result += "%3D" // =
    default: result.unicodeScalars.append(scalar)
    }
  }
  return result
}

private func _animationStyleSnapshot(_ node: _RenderNode, inherited: _NodeValues = .init()) -> String {
  var styles = inherited
  for (key, value) in node.styles { styles[key] = value }
  return styles.keys.sorted().filter { key in
    key != "transition" && key != "animation" && key != "animation-name"
  }.map { key in
    "\(key)=\(_animationEscaped(styles[key] ?? ""))"
  }.joined(separator: ";")
}

private func _encodeKeyframeTracks(_ tracks: [KeyframeTrackDescriptor]) -> String {
  tracks.map { track in
    let path = _animationEscaped(track.keyPath ?? "self")
    let segments = track.segments.map {
      "\($0.kind.rawValue),\(_animationNumber($0.duration)),\(_animationEscaped($0.valueDescription)),\(_animationEscaped($0.timingCurve.rawValue))"
    }.joined(separator: "+")
    return "\(path):\(segments)"
  }.joined(separator: "|")
}

private func _applyPhaseAnimationMetadata<Phase: Equatable>(
  to node: _RenderNode,
  phases: [Phase],
  frames: [_RenderNode],
  triggerDescription: String?,
  animations: [Animation?],
  styleFrames: [String]? = nil
) {
  node.attributes["data-phase-animator"] = "true"
  node.attributes["data-phase-repeating"] = triggerDescription == nil ? "true" : "false"
  node.attributes["data-phase-trigger"] = triggerDescription ?? ""
  node.attributes["data-phase-count"] = String(frames.count)
  node.attributes["data-phase-values"] = phases.map { _animationEscaped(_swiftUIWebDescribe($0)) }.joined(separator: "|")
  node.attributes["data-phase-frames"] = (styleFrames ?? frames.map { _animationStyleSnapshot($0) }).joined(separator: "|")
  node.attributes["data-phase-durations"] = animations.map { animation in
    guard let animation else { return "0" }
    return _animationNumber(_animationDuration(animation))
  }.joined(separator: ",")
  node.attributes["data-phase-easing"] = animations.map { $0?._timingFunction ?? "none" }.map(_animationEscaped).joined(separator: ",")
  // A phase whose animation has a delay holds where it is for that long before it moves on.
  let delays = animations.map { $0?._playedDelay ?? 0 }
  if delays.contains(where: { $0 > 0 }) { node.attributes["data-phase-delays"] = delays.map(_animationNumber).joined(separator: ",") }
}

/// The context an animator renders one of its samples in. Only the first sample of a container is mounted; the others are
/// read for their styles and discarded, so they render speculatively: what they contain (a child animator's trigger, a
/// value-scoped animation) must not advance the history of the mounted one, which shares their path.
@MainActor func _animatorSampleContext(_ context: _RenderContext, mounted: Bool) -> _RenderContext {
  guard !mounted else { return context }
  var sample = context
  sample._speculative = true
  return sample
}

/// The trigger of an animator as the page reads it: a generation that advances when the value stops being equal to the one
/// rendered there before, as a task's identity does. A description would not do: in Embedded Swift every struct, and every
/// enum without a raw value, describes itself the same way, so a change of such a trigger never reached the page.
typealias _TriggerGeneration = @MainActor (StateStore, String) -> UInt64

@MainActor func _triggerToken(_ generation: _TriggerGeneration?, key: String, context: _RenderContext) -> String? {
  guard let generation else { return nil }
  // A speculative render (the hovered look of a hover effect) must not advance the history of the real one.
  return context._speculative ? "" : String(generation(context.stateStore, key))
}

@MainActor func _triggerToken<Trigger: Equatable>(_ trigger: Trigger?, key: String, context: _RenderContext) -> String? {
  guard let trigger else { return nil }
  return context._speculative ? "" : String(context.stateStore._identityGeneration(key: key, value: trigger))
}

private func _animationDuration(_ animation: Animation) -> Double {
  // Animation intentionally keeps its detailed timing private. Its CSS
  // representation is stable and starts with `all <milliseconds>ms`.
  animation._playedDuration
}
