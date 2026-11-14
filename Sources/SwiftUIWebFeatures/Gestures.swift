@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

public extension Gesture {
  nonisolated func onChanged(_ action: @escaping (Self.Value) -> Void) -> _ChangedGesture<Self> {
    _ChangedGesture(base: self, action: _mainActor(action))
  }

  nonisolated func onEnded(_ action: @escaping (Self.Value) -> Void) -> _EndedGesture<Self> {
    _EndedGesture(base: self, action: _mainActor(action))
  }

  nonisolated func map<T>(_ body: @escaping (Self.Value) -> T) -> _MapGesture<Self, T> {
    _MapGesture(base: self, transform: body)
  }

  nonisolated func simultaneously<Other: Gesture>(with other: Other) -> SimultaneousGesture<Self, Other> { SimultaneousGesture(self, other) }

  @MainActor @preconcurrency func sequenced<Other: Gesture>(before other: Other) -> SequenceGesture<Self, Other> { SequenceGesture(self, other) }

  nonisolated func exclusively<Other: Gesture>(before other: Other) -> ExclusiveGesture<Self, Other> { ExclusiveGesture(self, other) }
}

/// The type-erased SwiftUI gesture.  Its value is the wrapped gesture's value.
public nonisolated struct AnyGesture<Value>: Gesture {
  public typealias Body = Never
  let erased: _RendererGesture
  let decodeValue: @MainActor (String) -> Value?
  let defaultValue: @MainActor () -> Value?

  public nonisolated init<G: Gesture>(_ gesture: G) where G.Value == Value {
    // SAFETY: gestures are only erased and read by the main-actor runtime; this entry point is nonisolated like SwiftUI's.
    nonisolated(unsafe) let gesture = gesture
    erased = _assumeMainActor { gesture._makeRendererGesture() }
    decodeValue = { gesture._rendererValue(from: $0) }
    defaultValue = { gesture._rendererDefaultValue() }
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture { erased.cloned() }
  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? { decodeValue(raw) }
  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? { defaultValue() }
}

public nonisolated struct TapGesture: Gesture, Hashable, Sendable {
  public typealias Value = Void
  public typealias Body = Never
  public let count: Int
  public nonisolated init(count: Int = 1) { self.count = max(1, count) }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    _RendererGesture(name: "tap", spec: _GestureSpec(kind: "tap", count: count))
  }
}

/// A tap that reports where it happened. The browser host reports taps
/// without a position, so the location is the zero point unless the host
/// supplies an `x,y` payload.
public nonisolated struct SpatialTapGesture: Gesture, Hashable, Sendable {
  public struct Value: Equatable, Sendable {
    public let location: CGPoint
    init(location: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint) { self.location = location }

    fileprivate init(raw: String) {
      let values = raw.split(separator: ",").compactMap { Double($0) }
      guard values.count >= 2 else { self.init(); return }
      self.init(location: CGPoint(x: values[0], y: values[1]))
    }
  }

  public typealias Body = Never
  public let count: Int
  public let coordinateSpace: CoordinateSpace

  @_disfavoredOverload public nonisolated init(count: Int = 1, coordinateSpace: CoordinateSpace = .local) {
    self.count = max(1, count)
    self.coordinateSpace = coordinateSpace
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    _RendererGesture(name: "tap", spec: _GestureSpec(kind: "tap", count: count, coordinateSpace: coordinateSpace))
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? {
    Value(raw: _gesturePayload(raw))
  }

  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? { Value() }
}

/// SwiftUI's deprecated magnification gesture. Its value is the magnification
/// alone, so it reuses the magnify recognizer and projects that field.
public nonisolated struct MagnificationGesture: Gesture, Sendable {
  public typealias Value = CGFloat
  public typealias Body = Never
  public var minimumScaleDelta: CGFloat

  public nonisolated init(minimumScaleDelta: CGFloat = 0.01) {
    self.minimumScaleDelta = max(0, minimumScaleDelta)
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    MagnifyGesture(minimumScaleDelta: minimumScaleDelta)._makeRendererGesture()
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> CGFloat? {
    MagnifyGesture.Value(raw: _gesturePayload(raw))?.magnification
  }

  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> CGFloat? { MagnifyGesture.Value().magnification }
}

/// SwiftUI's deprecated rotation gesture; its value is the rotation alone.
public nonisolated struct RotationGesture: Gesture, Sendable {
  public typealias Value = Angle
  public typealias Body = Never
  public var minimumAngleDelta: Angle

  public nonisolated init(minimumAngleDelta: Angle = .degrees(1)) {
    self.minimumAngleDelta = minimumAngleDelta
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    RotateGesture(minimumAngleDelta: minimumAngleDelta)._makeRendererGesture()
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Angle? {
    RotateGesture.Value(raw: _gesturePayload(raw))?.rotation
  }

  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Angle? { RotateGesture.Value().rotation }
}

public nonisolated struct LongPressGesture: Gesture, Hashable, Sendable {
  public typealias Value = Bool
  public typealias Body = Never
  public let minimumDuration: Double
  public nonisolated var maximumDistance: CGFloat

  public nonisolated init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
    self.minimumDuration = max(0, minimumDuration)
    self.maximumDistance = max(0, maximumDistance)
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    _RendererGesture(name: "longpress", spec: _GestureSpec(kind: "longpress", minimumDuration: minimumDuration, maximumDistance: Double(maximumDistance)))
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Bool? {
    let payload = _gesturePayload(raw)
    return payload != "false" && payload != "cancelled"
  }

  /// A press that ends without a payload was recognized.
  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Bool? { true }
}

/// The gesture produced by `onEnded(_:)`.
public nonisolated struct _EndedGesture<Base: Gesture>: Gesture {
  public typealias Value = Base.Value
  public typealias Body = Never
  let base: Base
  let action: @MainActor (Base.Value) -> Void

  nonisolated init(base: Base, action: @escaping @MainActor (Base.Value) -> Void) {
    self.base = base
    self.action = action
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    let erased = base._makeRendererGesture().cloned()
    let base = self.base
    let action = self.action
    let previous = erased.actionBox.ended
    let previousAction = erased.actionBox.endedAction
    erased.actionBox.ended = { raw in
      previous?(raw)
      if let value = base._rendererValue(from: raw) { action(value) }
    }
    // Core-only hosts may dispatch a terminal phase without a payload. SwiftUI
    // still invokes the end callback, so use the value's default representation.
    erased.actionBox.endedAction = {
      previousAction?()
      if let value = base._rendererDefaultValue() { action(value) }
    }
    return erased
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? { base._rendererValue(from: raw) }
  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? { base._rendererDefaultValue() }
}

/// The gesture produced by `map(_:)`.
public nonisolated struct _MapGesture<Base: Gesture, Value>: Gesture {
  public typealias Body = Never
  let base: Base
  let transform: (Base.Value) -> Value

  nonisolated init(base: Base, transform: @escaping (Base.Value) -> Value) {
    self.base = base
    self.transform = transform
  }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture { base._makeRendererGesture() }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? {
    base._rendererValue(from: raw).map(transform)
  }

  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? {
    base._rendererDefaultValue().map(transform)
  }
}

/// SwiftUI exposes composition as concrete generic gesture values. Each
/// wrapper's renderer erasure combines its children's erasures, and each value
/// is decoded through the children's own `_rendererValue(from:)`.
public nonisolated struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture {
  public typealias Body = Never

  public struct Value {
    public let first: First.Value?
    public let second: Second.Value?

    init(first: First.Value? = nil, second: Second.Value? = nil) {
      self.first = first; self.second = second
    }
  }

  public let first: First
  public let second: Second
  public nonisolated init(_ first: First, _ second: Second) { self.first = first; self.second = second }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    _compose(first, second, .simultaneous)
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? {
    let (kind, _) = _payloadAndKind(raw)
    if let kind {
      if _gestureKind(First.Value.self) == kind { return .init(first: first._rendererValue(from: raw), second: nil) }
      if _gestureKind(Second.Value.self) == kind { return .init(first: nil, second: second._rendererValue(from: raw)) }
    }
    return .init(first: first._rendererValue(from: raw), second: nil)
  }

  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? { Value() }
}

public nonisolated struct SequenceGesture<First: Gesture, Second: Gesture>: Gesture {
  public typealias Body = Never

  public enum Value {
    case first(First.Value)
    case second(First.Value, Second.Value?)
  }

  public let first: First
  public let second: Second
  /// The first gesture's latest value, shared by copies of this value so the
  /// second gesture's events can be paired with it.
  private let capture = _SequenceCapture<First.Value>()

  public nonisolated init(_ first: First, _ second: Second) { self.first = first; self.second = second }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    let result = _compose(first, second, .sequenced)
    let this = self
    let previousChanged = result.actionBox.changed
    result.actionBox.changed = { raw in
      previousChanged?(raw)
      // Recording the first value here keeps the pairing correct even when
      // the sequence has no changed callback of its own.
      _ = this._rendererValue(from: raw)
    }
    let previousReset = result.actionBox.reset
    let capture = self.capture
    result.actionBox.reset = {
      capture.first = nil
      previousReset?()
    }
    return result
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? {
    let (kind, _) = _payloadAndKind(raw)
    if kind == "second" || (_gestureKind(Second.Value.self) == kind) {
      guard let firstValue = capture.first ?? _defaultGestureValue(First.Value.self) else { return nil }
      return .second(firstValue, second._rendererValue(from: raw))
    }
    guard let value = first._rendererValue(from: raw) else { return nil }
    capture.first = value
    return .first(value)
  }

  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? {
    guard let firstValue = _defaultGestureValue(First.Value.self) else { return nil }
    return .second(firstValue, second._rendererDefaultValue())
  }
}

public nonisolated struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture {
  public typealias Body = Never

  public enum Value {
    case first(First.Value)
    case second(Second.Value)
  }

  public let first: First
  public let second: Second
  public nonisolated init(_ first: First, _ second: Second) { self.first = first; self.second = second }

  @MainActor @_spi(Renderer) public func _makeRendererGesture() -> _RendererGesture {
    _compose(first, second, .exclusive)
  }

  @MainActor @_spi(Renderer) public func _rendererValue(from raw: String) -> Value? {
    let (kind, _) = _payloadAndKind(raw)
    if kind == "second" || (_gestureKind(Second.Value.self) == kind) {
      guard let value = second._rendererValue(from: raw) else { return nil }
      return .second(value)
    }
    guard let value = first._rendererValue(from: raw) else { return nil }
    return .first(value)
  }

  @MainActor @_spi(Renderer) public func _rendererDefaultValue() -> Value? {
    guard let firstValue = _defaultGestureValue(First.Value.self) else { return nil }
    return .first(firstValue)
  }
}

// Composition values are conditionally equatable/hashable exactly when the
// child values are. This keeps SwiftUI call sites that compare or store a
// gesture value source-compatible without imposing constraints on custom
// third-party gesture payloads.
extension SimultaneousGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}

extension SimultaneousGesture.Value: Hashable where First.Value: Hashable, Second.Value: Hashable {}

extension SequenceGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}

extension SequenceGesture.Value: Hashable where First.Value: Hashable, Second.Value: Hashable {}

extension ExclusiveGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}

extension ExclusiveGesture.Value: Hashable where First.Value: Hashable, Second.Value: Hashable {}

private final class _SequenceCapture<Value> { var first: Value?; init() {} }

private func _gestureKind<Value>(_ type: Value.Type) -> String? {
  if Value.self == DragGesture.Value.self { return "drag" }
  if Value.self == MagnifyGesture.Value.self { return "magnify" }
  if Value.self == RotateGesture.Value.self { return "rotate" }
  if Value.self == Bool.self { return "longpress" }
  if Value.self == Void.self { return "tap" }
  return nil
}

@MainActor private func _compose<A: Gesture, B: Gesture>(_ firstGesture: A, _ secondGesture: B, _ composition: _GestureComposition) -> _RendererGesture {
  let first = firstGesture._makeRendererGesture()
  let second = secondGesture._makeRendererGesture()
  let spec = _GestureSpec(kind: "composition", composition: composition, first: first._swiftUIWebSpec.encoded, second: second._swiftUIWebSpec.encoded)
  let result = _RendererGesture(name: composition.rawValue, spec: spec)
  // Browser composition events may carry a small `kind|payload` tag so a
  // drag value is not accidentally decoded as a magnification (or rotation)
  // value. Static hosts and tests can still dispatch an untagged value, which
  // preserves the historical fan-out behavior.
  result.actionBox.changed = { raw in
    _routeCompositionValue(raw, expected: first._swiftUIWebSpec.kind, action: first.actionBox.changed)
    _routeCompositionValue(raw, expected: second._swiftUIWebSpec.kind, action: second.actionBox.changed)
  }
  result.actionBox.ended = { raw in
    _routeCompositionValue(raw, expected: first._swiftUIWebSpec.kind, action: first.actionBox.ended)
    _routeCompositionValue(raw, expected: second._swiftUIWebSpec.kind, action: second.actionBox.ended)
  }
  result.actionBox.endedAction = { first.actionBox.endedAction?(); second.actionBox.endedAction?() }
  result.actionBox.cancelled = { raw in first.actionBox.cancelled?(raw); second.actionBox.cancelled?(raw) }
  result.actionBox.reset = { first.actionBox.reset?(); second.actionBox.reset?() }
  return result
}

@MainActor private func _routeCompositionValue(_ raw: String, expected: String, action: (@MainActor (String) -> Void)?) {
  guard let separator = raw.firstIndex(of: "|") else {
    action?(raw)
    return
  }
  let kind = String(raw[..<separator])
  // A nested composition owns the routing for its descendants. Forward the
  // tagged payload intact so its own `_compose` box can match the concrete
  // child kind instead of dropping a valid drag/transform update at the outer
  // composition boundary.
  if expected == "composition" {
    action?(raw)
    return
  }
  guard kind == expected else { return }
  action?(String(raw[raw.index(after: separator)...]))
}
