// SwiftUI-shaped gesture protocol, values and composition wrappers, plus the
// renderer-neutral gesture descriptor.
//
// Gesture recognition is deliberately split in two layers.  This file owns
// the public values, composition and callback semantics; the browser target
// consumes the compact descriptor emitted by GestureCompatibilityModifier.
// No DOM, JavaScript or browser event types are visible here.
//
// Each gesture erases itself through `_makeRendererGesture()`.  Primitive
// gestures describe their recognizer; wrappers such as `_ChangedGesture` add
// callbacks to the erasure of the gesture they wrap.  Typed values travel the
// other way through `_rendererValue(from:)`, so no wrapper needs to know the
// concrete gesture it observes.



@_spi(Renderer) public enum _GestureComposition: String, Hashable, Sendable {
  case none, simultaneous, sequenced, exclusive, highPriority, lowPriority
}

@_spi(Renderer) public struct _GestureSpec: Hashable, Sendable {
  public var kind: String
  public var count: Int
  public var minimumDistance: Double
  public var minimumDuration: Double
  public var maximumDistance: Double
  public var minimumScaleDelta: Double
  public var minimumAngleDelta: Double
  public var coordinateSpace: String
  public var transientRendering: Bool
  public var composition: _GestureComposition
  public var first: String?
  public var second: String?

  public nonisolated init(
    kind: String,
    count: Int = 1,
    minimumDistance: Double = 10,
    minimumDuration: Double = 0.5,
    maximumDistance: Double = 10,
    minimumScaleDelta: Double = 0.01,
    minimumAngleDelta: Double = 0.01,
    transientRendering: Bool = false,
    coordinateSpace: CoordinateSpace = .local,
    composition: _GestureComposition = .none,
    first: String? = nil,
    second: String? = nil
  ) {
    self.kind = kind
    self.count = max(1, count)
    self.minimumDistance = max(0, minimumDistance)
    self.minimumDuration = max(0, minimumDuration)
    self.maximumDistance = max(0, maximumDistance)
    self.minimumScaleDelta = max(0, minimumScaleDelta)
    self.minimumAngleDelta = max(0, minimumAngleDelta)
    self.transientRendering = transientRendering
    self.coordinateSpace = coordinateSpace._swiftUIWebName
    self.composition = composition
    self.first = first
    self.second = second
  }

  /// Stable, escaped metadata used by browser hosts.  Values are numeric or
  /// identifier strings, so escaping is intentionally tiny and deterministic.
  public var encoded: String {
    var fields = [
      "kind=\(kind._gestureEscaped)",
      "count=\(count)",
      "minDistance=\(minimumDistance._gestureClean)",
      "minDuration=\(minimumDuration._gestureClean)",
      "maxDistance=\(maximumDistance._gestureClean)",
      "minScale=\(minimumScaleDelta._gestureClean)",
      "minAngle=\(minimumAngleDelta._gestureClean)",
      "space=\(coordinateSpace._gestureEscaped)",
      "composition=\(composition.rawValue)"
    ]
    if let first { fields.append("first=\(first._gestureEscaped)") }
    if let second { fields.append("second=\(second._gestureEscaped)") }
    if transientRendering { fields.append("transient=true") }
    return fields.joined(separator: ";")
  }
}

@MainActor package final class _GestureActionBox {
  package var changed: (@MainActor (String) -> Void)?
  package var ended: (@MainActor (String) -> Void)?
  package var endedAction: (@MainActor () -> Void)?
  package var cancelled: (@MainActor (String) -> Void)?
  package var reset: (@MainActor () -> Void)?
}

// Swift 6.4 enforces exclusivity for an `inout` property-wrapper capture in
// an escaping closure. Keep the wrapper in a tiny reference box so gesture
// callbacks can mutate shared state without capturing an immutable local
// value or the caller's `inout` storage directly.
@MainActor private final class _GestureStateCapture<Value> {
  var state: GestureState<Value>
  init(_ state: GestureState<Value>) { self.state = state }
}

/// The renderer's erasure of a gesture: its recognizer descriptor plus the
/// raw-event callbacks that the composition wrappers attached.
@_spi(Renderer) public struct _RendererGesture: Hashable, Sendable {
  public let name: String
  public let _swiftUIWebSpec: _GestureSpec
  package let actionBox: _GestureActionBox

  nonisolated package init(name: String, spec: _GestureSpec, box: _GestureActionBox = _GestureActionBox()) {
    self.name = name
    self._swiftUIWebSpec = spec
    self.actionBox = box
  }

  nonisolated public static func == (lhs: _RendererGesture, rhs: _RendererGesture) -> Bool {
    lhs.name == rhs.name && lhs._swiftUIWebSpec == rhs._swiftUIWebSpec
  }

  nonisolated public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
    hasher.combine(_swiftUIWebSpec)
  }

  /// A copy with its own callback box. Wrappers add their callbacks to a copy,
  /// so the gesture they wrap keeps its own callbacks (value semantics).
  @MainActor package func cloned() -> _RendererGesture {
    let box = _GestureActionBox()
    box.changed = actionBox.changed
    box.ended = actionBox.ended
    box.endedAction = actionBox.endedAction
    box.cancelled = actionBox.cancelled
    box.reset = actionBox.reset
    return _RendererGesture(name: name, spec: _swiftUIWebSpec, box: box)
  }
}

/// SwiftUI's gesture protocol.  `_makeRendererGesture()`, `_rendererValue(from:)`
/// and `_rendererDefaultValue()` are the renderer's hooks; they are SPI with
/// defaults so application gestures only write `body` (or a primitive
/// gesture's own initializers).
@MainActor @preconcurrency public protocol Gesture<Value> {
  associatedtype Value
  associatedtype Body: Gesture
  @MainActor @preconcurrency var body: Body { get }

  @MainActor @_spi(Renderer) func _makeRendererGesture() -> _RendererGesture
  @MainActor @_spi(Renderer) func _rendererValue(from raw: String) -> Value?
  @MainActor @_spi(Renderer) func _rendererDefaultValue() -> Value?
}

public extension Gesture {
  @MainActor @_spi(Renderer) func _makeRendererGesture() -> _RendererGesture {
    guard Body.self != Never.self else {
      let name = _swiftUIWebTypeName(Self.self)
      return _RendererGesture(name: name, spec: _GestureSpec(kind: name))
    }
    return body._makeRendererGesture()
  }

  @MainActor @_spi(Renderer) func _rendererValue(from raw: String) -> Value? {
    _decodeGestureValue(Value.self, raw: raw)
  }

  @MainActor @_spi(Renderer) func _rendererDefaultValue() -> Value? {
    _defaultGestureValue(Value.self)
  }

  @MainActor @preconcurrency func updating<State>(
    _ state: GestureState<State>,
    body: @escaping (Self.Value, inout State, inout Transaction) -> Void
  ) -> GestureStateGesture<Self, State> {
    GestureStateGesture(base: self, state: state, body: body)
  }

}

public extension Gesture where Body == Never {
  /// Primitive gestures are leaves; their recognizers are described by
  /// `_makeRendererGesture()` instead of a body.
  var body: Never {
    fatalError("A primitive gesture has no body")
  }
}

extension Never: Gesture {
  public typealias Value = Never
  @_spi(Renderer) nonisolated public var body: Never { fatalError("Never has no gesture body") }
}

// MARK: - Primitive gestures

@MainActor @preconcurrency public struct DragGesture: Gesture, Hashable, Sendable {
  public struct Value: Equatable, Sendable {
    public let time: Date
    public let location: CGPoint
    public let startLocation: CGPoint
    public let translation: CGSize
    /// SwiftUI derives velocity from the predicted end location. Keep the
    /// value explicit so custom gesture code can use the same API without
    /// asking the browser for another measurement.
    public let velocity: CGSize
    public let predictedEndLocation: CGPoint
    public let predictedEndTranslation: CGSize

    init(
      time: Date = Date(timeIntervalSince1970: 0),
      location: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint,
      startLocation: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint,
      translation: CGSize = _SwiftUIWebGeometryDefaults.zeroSize,
      velocity: CGSize? = nil,
      predictedEndLocation: CGPoint? = nil,
      predictedEndTranslation: CGSize? = nil
    ) {
      self.time = time; self.location = location; self.startLocation = startLocation
      self.translation = translation
      self.predictedEndLocation = predictedEndLocation ?? location
      self.predictedEndTranslation = predictedEndTranslation ?? translation
      self.velocity = velocity ?? CGSize(
        width: (self.predictedEndLocation.x - location.x) * 4,
        height: (self.predictedEndLocation.y - location.y) * 4
      )
    }

    fileprivate init?(raw: String) {
      let values = raw.split(separator: ",").compactMap { Double($0) }
      guard values.count >= 6 else { return nil }
      let time = Date(timeIntervalSince1970: values.count > 8 ? values[8] : 0)
      self.init(
        time: time,
        location: CGPoint(x: values[0], y: values[1]),
        startLocation: CGPoint(x: values[2], y: values[3]),
        translation: CGSize(width: values[0] - values[2], height: values[1] - values[3]),
        predictedEndLocation: values.count >= 8 ? CGPoint(x: values[6], y: values[7]) : nil,
        predictedEndTranslation: values.count >= 9 ? CGSize(width: values[6] - values[2], height: values[7] - values[3]) : nil
      )
    }
  }

  public typealias Body = Never
  @MainActor @preconcurrency public let minimumDistance: CGFloat
  @MainActor @preconcurrency public let coordinateSpace: CoordinateSpace

  private var _transientRendering = false
  @_disfavoredOverload @MainActor @preconcurrency public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {
    self.minimumDistance = max(0, minimumDistance); self.coordinateSpace = coordinateSpace
  }

  /// Lets the browser track the drag with a temporary CSS translation. In the
  /// browser, intermediate `onChanged` callbacks are suppressed so the model
  /// can commit once from `onEnded`; cancellation restores the original
  /// rendering. Ordinary drag gestures keep their existing callback behavior.
  @_spi(Renderer) public func transientRendering() -> DragGesture {
    var result = self
    result._transientRendering = true
    return result
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    _RendererGesture(name: "drag", spec: _GestureSpec(
      kind: "drag",
      minimumDistance: Double(minimumDistance),
      transientRendering: _transientRendering,
      coordinateSpace: coordinateSpace
    ))
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? {
    Value(raw: _gesturePayload(raw))
  }

  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? { Value() }
}

public nonisolated struct MagnifyGesture: Gesture, Hashable, Sendable {
  public struct Value: Equatable, Sendable {
    public let time: Date
    public let magnification: CGFloat
    public let velocity: CGFloat
    public let startAnchor: UnitPoint
    public let startLocation: CGPoint
    let startMagnification: CGFloat
    let location: CGPoint

    package init(magnification: CGFloat = 1, startMagnification: CGFloat = 1, velocity: CGFloat = 0, time: Date = Date(timeIntervalSince1970: 0), startAnchor: UnitPoint = .center, startLocation: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint, location: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint) {
      self.magnification = magnification; self.startMagnification = startMagnification; self.velocity = velocity; self.time = time; self.startAnchor = startAnchor; self.startLocation = startLocation; self.location = location
    }

    package init?(raw: String) {
      let values = raw.split(separator: ",").compactMap { Double($0) }
      guard let magnification = values.first else { return nil }
      self.init(magnification: magnification, startMagnification: values.count > 1 ? values[1] : 1, velocity: values.count > 2 ? values[2] : 0, time: Date(timeIntervalSince1970: values.count > 3 ? values[3] : 0), startLocation: CGPoint(x: values.count > 4 ? values[4] : 0, y: values.count > 5 ? values[5] : 0), location: CGPoint(x: values.count > 6 ? values[6] : 0, y: values.count > 7 ? values[7] : 0))
    }
  }

  public typealias Body = Never
  public var minimumScaleDelta: CGFloat
  @_spi(Renderer) public var coordinateSpace: CoordinateSpace

  public nonisolated init(minimumScaleDelta: CGFloat = 0.01) {
    self.minimumScaleDelta = max(0, minimumScaleDelta)
    self.coordinateSpace = .local
  }

  @_spi(Renderer) public init(minimumScaleDelta: CGFloat = 0.01, coordinateSpace: CoordinateSpace) {
    self.minimumScaleDelta = max(0, minimumScaleDelta)
    self.coordinateSpace = coordinateSpace
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    _RendererGesture(name: "magnify", spec: _GestureSpec(kind: "magnify", minimumScaleDelta: Double(minimumScaleDelta), coordinateSpace: coordinateSpace))
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? {
    Value(raw: _gesturePayload(raw))
  }

  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? { Value() }
}

public nonisolated struct RotateGesture: Gesture, Hashable, Sendable {
  public struct Value: Equatable, Sendable {
    public let time: Date
    public let rotation: Angle
    public let velocity: Angle
    public let startAnchor: UnitPoint
    public let startLocation: CGPoint
    let startRotation: Angle
    let location: CGPoint

    package init(rotation: Angle = .zero, startRotation: Angle = .zero, velocity: Angle = .zero, time: Date = Date(timeIntervalSince1970: 0), startAnchor: UnitPoint = .center, startLocation: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint, location: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint) {
      self.rotation = rotation; self.startRotation = startRotation; self.velocity = velocity; self.time = time; self.startAnchor = startAnchor; self.startLocation = startLocation; self.location = location
    }

    package init?(raw: String) {
      let values = raw.split(separator: ",").compactMap { Double($0) }
      guard let angle = values.first else { return nil }
      self.init(rotation: .radians(angle), startRotation: .radians(values.count > 1 ? values[1] : 0), velocity: .radians(values.count > 2 ? values[2] : 0), time: Date(timeIntervalSince1970: values.count > 3 ? values[3] : 0), startLocation: CGPoint(x: values.count > 4 ? values[4] : 0, y: values.count > 5 ? values[5] : 0), location: CGPoint(x: values.count > 6 ? values[6] : 0, y: values.count > 7 ? values[7] : 0))
    }
  }

  public typealias Body = Never
  public var minimumAngleDelta: Angle
  @_spi(Renderer) public var coordinateSpace: CoordinateSpace

  public nonisolated init(minimumAngleDelta: Angle = .degrees(1)) {
    self.minimumAngleDelta = minimumAngleDelta
    self.coordinateSpace = .local
  }

  @_spi(Renderer) public init(minimumAngleDelta: Angle = .degrees(1), coordinateSpace: CoordinateSpace) {
    self.minimumAngleDelta = minimumAngleDelta
    self.coordinateSpace = coordinateSpace
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    _RendererGesture(name: "rotate", spec: _GestureSpec(kind: "rotate", minimumAngleDelta: abs(minimumAngleDelta.radians), coordinateSpace: coordinateSpace))
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? {
    Value(raw: _gesturePayload(raw))
  }

  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? { Value() }
}

// MARK: - Callback wrappers

/// The gesture produced by `onChanged(_:)`.
public nonisolated struct _ChangedGesture<Base: Gesture>: Gesture {
  public typealias Value = Base.Value
  public typealias Body = Never
  let base: Base
  let action: @MainActor (Base.Value) -> Void

  nonisolated package init(base: Base, action: @escaping @MainActor (Base.Value) -> Void) {
    self.base = base
    self.action = action
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    let erased = base._makeRendererGesture().cloned()
    let base = self.base
    let action = self.action
    let previous = erased.actionBox.changed
    erased.actionBox.changed = { raw in
      previous?(raw)
      if let value = base._rendererValue(from: raw) { action(value) }
    }
    return erased
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? { base._rendererValue(from: raw) }
  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? { base._rendererDefaultValue() }
}

/// The gesture produced by `updating(_:body:)`: it keeps the wrapped gesture's
/// value and writes the body's result into `state` while the gesture runs.
public nonisolated struct GestureStateGesture<Base: Gesture, State>: Gesture {
  public typealias Value = Base.Value
  public typealias Body = Never
  public let base: Base
  public let state: GestureState<State>
  let update: @MainActor (Base.Value, inout State, inout Transaction) -> Void

  public nonisolated init(base: Base, state: GestureState<State>, body: @escaping (GestureStateGesture<Base, State>.Value, inout State, inout Transaction) -> Void) {
    self.base = base
    self.state = state
    // SAFETY: the update closure is only invoked by the main-actor runtime, like every gesture callback.
    nonisolated(unsafe) let body = body
    self.update = { value, current, transaction in body(value, &current, &transaction) }
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    let erased = base._makeRendererGesture().cloned()
    let base = self.base
    let captured = _GestureStateCapture(state)
    let update = self.update
    let previous = erased.actionBox.changed
    erased.actionBox.changed = { raw in
      previous?(raw)
      guard let typed = base._rendererValue(from: raw) else { return }
      var value = captured.state.wrappedValue
      var transaction = Transaction()
      update(typed, &value, &transaction)
      captured.state.wrappedValue = value
    }
    let previousReset = erased.actionBox.reset
    erased.actionBox.reset = {
      captured.state._reset()
      previousReset?()
    }
    return erased
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? { base._rendererValue(from: raw) }
  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? { base._rendererDefaultValue() }
}

// MARK: - Composition

package func _payloadAndKind(_ raw: String) -> (String?, String) {
  guard let separator = raw.firstIndex(of: "|") else { return (nil, raw) }
  return (String(raw[..<separator]), String(raw[raw.index(after: separator)...]))
}

package func _gesturePayload(_ raw: String) -> String {
  _payloadAndKind(raw).1
}

private func _decodeGestureValue<Value>(_ type: Value.Type, raw: String) -> Value? {
  let payload = _gesturePayload(raw)
  if Value.self == DragGesture.Value.self { return DragGesture.Value(raw: payload) as? Value }
  if Value.self == MagnifyGesture.Value.self { return MagnifyGesture.Value(raw: payload) as? Value }
  if Value.self == RotateGesture.Value.self { return RotateGesture.Value(raw: payload) as? Value }
  if Value.self == Bool.self { return (payload != "false" && payload != "cancelled") as? Value }
  if Value.self == Int.self { return Int(payload) as? Value }
  if Value.self == Double.self { return Double(payload) as? Value }
  if Value.self == String.self { return payload as? Value }
  if Value.self == Void.self { return (() as Void) as? Value }
  return payload as? Value
}

package func _defaultGestureValue<Value>(_ type: Value.Type) -> Value? {
  if Value.self == Void.self { return (() as Void) as? Value }
  if Value.self == Bool.self { return false as? Value }
  if Value.self == DragGesture.Value.self { return DragGesture.Value() as? Value }
  if Value.self == MagnifyGesture.Value.self { return MagnifyGesture.Value() as? Value }
  if Value.self == RotateGesture.Value.self { return RotateGesture.Value() as? Value }
  return nil
}

private extension CoordinateSpace {
  var _swiftUIWebName: String {
    switch self { case .local: return "local"; case .global: return "global"; case .named(let name): return "named:\(name)" }
  }
}
private extension Double {
  var _gestureClean: String {
    guard isFinite else { return "0" }
    let value = String(self)
    return value.hasSuffix(".0") ? String(value.dropLast(2)) : value
  }
}
private extension String {
  var _gestureEscaped: String {
    var result = ""
    result.reserveCapacity(count)
    for character in self {
      if character == "\\" || character == ";" || character == "|" { result.append("\\") }
      result.append(character)
    }
    return result
  }
}
