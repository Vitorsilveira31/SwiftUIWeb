// Anchors: the geometry of one view, handed up through a preference and read in the coordinates of another
// (`GeometryProxy[anchor]`), and the modifiers that read a preference to draw an overlay or a background.

/// A value of a view's geometry (a point or a rectangle of it) that another view reads in its own coordinates, with
/// `GeometryProxy`'s subscript.
@frozen public struct Anchor<Value> {
  let _resolver: _AnchorResolver<Value>

  init(_ resolve: @escaping (_AnchorSpace) -> Value) { _resolver = _AnchorResolver(resolve) }

  /// The value in the coordinates of the view that reads it (`reader`).
  func _value(in reader: _AnchorSpace) -> Value { _resolver.resolve(reader) }

  /// The value in the coordinates of an unscaled view whose top-leading corner is at `origin` in the window.
  func _value(from origin: CGPoint) -> Value { _resolver.resolve(_AnchorSpace(origin: origin)) }

  /// What an anchor is made of: a point or rectangle of the view it is attached to, in that view's coordinates.
  @frozen public struct Source {
    let _make: (_AnchorFrame) -> Anchor<Value>
    init(_ make: @escaping (_AnchorFrame) -> Anchor<Value>) { _make = make }

    /// The anchor of an unscaled view whose frame in the window is `frame`.
    func _make(_ frame: CGRect) -> Anchor<Value> { _make(_AnchorFrame(space: _AnchorSpace(origin: frame.origin), size: frame.size)) }
  }
}

/// The coordinates of a view, for anchors: where its own top-leading corner is in the window and where its axes go there (a
/// point along x lands `a` across and `b` down, one along y lands `c` across and `d` down: the scales and rotations above
/// it). An anchor is made in the space of the view it is attached to and read in the reader's, which may be under other
/// transforms: it goes through the window.
@usableFromInline struct _AnchorSpace: Equatable, Sendable {
  var origin: CGPoint
  var a = 1.0
  var b = 0.0
  var c = 0.0
  var d = 1.0

  init(origin: CGPoint, scaleX: Double = 1, scaleY: Double = 1) { self.origin = origin; a = scaleX; d = scaleY }
  init(origin: CGPoint, axes: _GeometryAxes) { self.origin = origin; a = axes.a; b = axes.b; c = axes.c; d = axes.d }

  /// A point of this view, in the window.
  func window(_ point: CGPoint) -> CGPoint {
    CGPoint(x: origin.x + a * point.x + c * point.y, y: origin.y + b * point.x + d * point.y)
  }

  /// A point of the window, in this view's coordinates.
  func local(_ point: CGPoint) -> CGPoint {
    let dx = point.x - origin.x, dy = point.y - origin.y, determinant = a * d - b * c
    guard abs(determinant) > 1e-12 else { return CGPoint(x: dx, y: dy) }
    return CGPoint(x: (d * dx - c * dy) / determinant, y: (a * dy - b * dx) / determinant)
  }

  /// A point of this view, in the coordinates of `reader`.
  func point(_ point: CGPoint, in reader: _AnchorSpace) -> CGPoint { reader.local(window(point)) }

  /// A rectangle of this view, in the coordinates of `reader`: the box of its four corners there, since a rotation between
  /// the two turns it.
  func rect(_ rect: CGRect, in reader: _AnchorSpace) -> CGRect {
    let x0 = rect.origin.x, y0 = rect.origin.y, x1 = x0 + rect.size.width, y1 = y0 + rect.size.height
    let corners = [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x0, y: y1), CGPoint(x: x1, y: y1)].map { point($0, in: reader) }
    var minX = corners[0].x, maxX = minX, minY = corners[0].y, maxY = minY
    for corner in corners { minX = min(minX, corner.x); maxX = max(maxX, corner.x); minY = min(minY, corner.y); maxY = max(maxY, corner.y) }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }
}

extension _GeometryMeasurement {
  /// The view's coordinates for anchors: its own corner in the window and where its axes go there. An anchor is read in the
  /// reader's points, so transforms shared with the anchored view cancel and the others are converted.
  var anchorSpace: _AnchorSpace { _AnchorSpace(origin: corner, axes: resolvedAxes) }

  /// The view an anchor is made from: its space and the size it lays out at.
  var anchorFrame: _AnchorFrame { _AnchorFrame(space: anchorSpace, size: size) }
}

/// The view an anchor is made from: its space and the size it lays out at, in its own points.
@usableFromInline struct _AnchorFrame: Equatable, Sendable {
  var space: _AnchorSpace
  var size: CGSize
}

/// Resolves an anchor: the value, through the window, in the coordinates of the view that reads it.
@usableFromInline final class _AnchorResolver<Value> {
  let resolve: (_AnchorSpace) -> Value
  init(_ resolve: @escaping (_AnchorSpace) -> Value) { self.resolve = resolve }
}

extension Anchor: @unchecked Sendable where Value: Sendable {}
extension Anchor.Source: @unchecked Sendable where Value: Sendable {}

extension Anchor: Equatable where Value: Equatable {
  public static func == (lhs: Anchor<Value>, rhs: Anchor<Value>) -> Bool { lhs._value(from: .zero) == rhs._value(from: .zero) }
}

extension Anchor: Hashable where Value: Hashable {
  public func hash(into hasher: inout Hasher) { hasher.combine(_value(from: .zero)) }
}

extension Anchor.Source {
  /// The anchors of `array`, as one anchor of an array.
  public init<T>(_ array: [Anchor<T>.Source]) where Value == [T] {
    self.init { frame in
      let anchors = array.map { $0._make(frame) }
      return Anchor { reader in anchors.map { $0._value(in: reader) } }
    }
  }

  /// The anchor of `anchor`, if there is one.
  public init<T>(_ anchor: Anchor<T>.Source?) where Value == T? {
    self.init { frame in
      let made = anchor.map { $0._make(frame) }
      return Anchor { reader in made.map { $0._value(in: reader) } }
    }
  }
}

extension Anchor.Source where Value == CGPoint {
  /// The point `p` of the view.
  public static func point(_ p: CGPoint) -> Anchor<Value>.Source {
    Anchor.Source { frame in
      Anchor { reader in frame.space.point(p, in: reader) }
    }
  }

  /// The point of the view at `p`, a fraction of its size.
  public static func unitPoint(_ p: UnitPoint) -> Anchor<Value>.Source {
    Anchor.Source { frame in
      Anchor { reader in frame.space.point(CGPoint(x: frame.size.width * p.x, y: frame.size.height * p.y), in: reader) }
    }
  }

  public static var topLeading: Anchor<CGPoint>.Source { unitPoint(.topLeading) }
  public static var top: Anchor<CGPoint>.Source { unitPoint(.top) }
  public static var topTrailing: Anchor<CGPoint>.Source { unitPoint(.topTrailing) }
  public static var leading: Anchor<CGPoint>.Source { unitPoint(.leading) }
  public static var center: Anchor<CGPoint>.Source { unitPoint(.center) }
  public static var trailing: Anchor<CGPoint>.Source { unitPoint(.trailing) }
  public static var bottomLeading: Anchor<CGPoint>.Source { unitPoint(.bottomLeading) }
  public static var bottom: Anchor<CGPoint>.Source { unitPoint(.bottom) }
  public static var bottomTrailing: Anchor<CGPoint>.Source { unitPoint(.bottomTrailing) }
}

extension Anchor.Source where Value == CGRect {
  /// The rectangle `r` of the view.
  public static func rect(_ r: CGRect) -> Anchor<Value>.Source {
    Anchor.Source { frame in
      Anchor { reader in frame.space.rect(r, in: reader) }
    }
  }

  /// The view's bounds.
  public static var bounds: Anchor<CGRect>.Source {
    Anchor.Source { frame in
      Anchor { reader in frame.space.rect(CGRect(x: 0, y: 0, width: frame.size.width, height: frame.size.height), in: reader) }
    }
  }
}

extension GeometryProxy {
  /// `anchor`'s value in the coordinates of the view this proxy measures.
  public subscript<T>(anchor: Anchor<T>) -> T {
    _access?.readsPosition = true
    return anchor._value(in: _measurement.anchorSpace)
  }
}

// MARK: Modifiers

public extension View {
  /// Gives the views above the preference `transform` makes of an anchor of this view.
  nonisolated func anchorPreference<A, K>(key _: K.Type = K.self, value: Anchor<A>.Source, transform: @escaping (Anchor<A>) -> K.Value) -> some View where K: PreferenceKey {
    _modified(_AnchorPreferenceModifier<A, K>(source: value, update: { result, anchor in result = transform(anchor) }, replaces: false))
  }

  /// Changes the preference this view's subtree gives the views above, with an anchor of this view.
  nonisolated func transformAnchorPreference<A, K>(key _: K.Type = K.self, value: Anchor<A>.Source, transform: @escaping (inout K.Value, Anchor<A>) -> Void) -> some View where K: PreferenceKey {
    _modified(_AnchorPreferenceModifier<A, K>(source: value, update: transform, replaces: true))
  }

  /// Changes the preference this view's subtree gives the views above.
  nonisolated func transformPreference<K>(_ key: K.Type = K.self, _ callback: @escaping (inout K.Value) -> Void) -> some View where K: PreferenceKey {
    _modified(_TransformPreferenceModifier<K>(callback: callback))
  }

  /// Draws, over this view, what `transform` makes of the preference its subtree gives.
  @_disfavoredOverload nonisolated func overlayPreferenceValue<Key, T>(_ key: Key.Type = Key.self, @ViewBuilder _ transform: @escaping (Key.Value) -> T) -> some View where Key: PreferenceKey, T: View {
    _modified(_PreferenceValueLayer<Key, T>(transform: transform, alignment: .center, overlay: true))
  }

  /// Draws, over this view and aligned by `alignment`, what `transform` makes of the preference its subtree gives.
  nonisolated func overlayPreferenceValue<K, V>(_ key: K.Type, alignment: Alignment = .center, @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View where K: PreferenceKey, V: View {
    _modified(_PreferenceValueLayer<K, V>(transform: transform, alignment: alignment, overlay: true))
  }

  /// Draws, behind this view, what `transform` makes of the preference its subtree gives.
  @_disfavoredOverload nonisolated func backgroundPreferenceValue<Key, T>(_ key: Key.Type = Key.self, @ViewBuilder _ transform: @escaping (Key.Value) -> T) -> some View where Key: PreferenceKey, T: View {
    _modified(_PreferenceValueLayer<Key, T>(transform: transform, alignment: .center, overlay: false))
  }

  /// Draws, behind this view and aligned by `alignment`, what `transform` makes of the preference its subtree gives.
  nonisolated func backgroundPreferenceValue<K, V>(_ key: K.Type, alignment: Alignment = .center, @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View where K: PreferenceKey, V: View {
    _modified(_PreferenceValueLayer<K, V>(transform: transform, alignment: alignment, overlay: false))
  }
}

/// Where the writes of a modifier's subtree start, taken before the subtree renders and read after.
final class _PreferenceScope {
  var start = 0
  /// Whether the texts were publishing their layout above the reader: the layer it draws publishes as they did.
  var publishedAbove = false
}

/// `anchorPreference` and `transformAnchorPreference`: the host measures the view's frame in the window
/// (`data-geometry-change`, also as an ancestor scrolls), Swift keeps it per path, and each render makes the anchor from
/// the frame measured last. A new frame renders the view again, and the views above with it.
nonisolated struct _AnchorPreferenceModifier<A, K: PreferenceKey>: ViewModifier {
  let source: Anchor<A>.Source
  let update: (inout K.Value, Anchor<A>) -> Void
  /// Whether the anchor changes the subtree's value (`transformAnchorPreference`) or adds a value of its own.
  let replaces: Bool
  let scope = _PreferenceScope()

  @MainActor func _modifyContext(_ context: inout _RenderContext) {
    if replaces { scope.start = context.preferenceStore._writeCount(for: K.self) }
  }

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    _renderRegistersWithAncestors()
    let key = context._compactPathID + "#anchor"
    let store = context.stateStore
    let target = node.kind == .fragment ? (node.children.first { !$0.isEmpty } ?? node) : node
    _measureWindowFrame(of: target, key: key, store: store, owner: context._renderOwnerToken, reader: context._preferenceLayerOwner)
    let anchor = source._make(_anchorFrame(key: key, store: store))
    let preferences = context.preferenceStore
    if replaces {
      var value = preferences.value(for: K.self, since: scope.start)
      update(&value, anchor)
      preferences.replace(value, for: K.self, since: scope.start)
    } else {
      var value = K.defaultValue
      update(&value, anchor)
      preferences.write(value, for: K.self)
    }
  }
}

/// `transformPreference`: the subtree's value, changed by the callback, is the one value the views above see.
nonisolated struct _TransformPreferenceModifier<K: PreferenceKey>: ViewModifier {
  let callback: (inout K.Value) -> Void
  let scope = _PreferenceScope()

  @MainActor func _modifyContext(_ context: inout _RenderContext) {
    scope.start = context.preferenceStore._writeCount(for: K.self)
    _notePreferenceReader(K.self, in: &context)
  }

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    _renderRegistersWithAncestors()
    let preferences = context.preferenceStore
    var value = preferences.value(for: K.self, since: scope.start)
    callback(&value)
    preferences.replace(value, for: K.self, since: scope.start)
  }
}

/// `overlayPreferenceValue` and `backgroundPreferenceValue`: the layer renders after the view's subtree, from the
/// preference that subtree gave.
nonisolated struct _PreferenceValueLayer<K: PreferenceKey, Layer: View>: ViewModifier {
  let transform: (K.Value) -> Layer
  let alignment: Alignment
  let overlay: Bool
  let scope = _PreferenceScope()

  @MainActor func _modifyContext(_ context: inout _RenderContext) {
    scope.start = context.preferenceStore._writeCount(for: K.self)
    scope.publishedAbove = context.environment._publishesTextLayout
    context._preferenceLayerOwner = context._renderOwnerToken
    _notePreferenceReader(K.self, in: &context)
  }

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    context.environment._publishesTextLayout = scope.publishedAbove
    // The layer renders here, on the main actor, before `_apply` returns.
    nonisolated(unsafe) let value = context.preferenceStore.value(for: K.self, since: scope.start)
    nonisolated(unsafe) let transform = self.transform
    if overlay {
      OverlayModifier(content: { transform(value) }, alignment: alignment)._apply(to: node, context: &context)
    } else {
      BackgroundModifier(content: { transform(value) }, alignment: alignment)._apply(to: node, context: &context)
    }
  }
}

/// A reader of `Text.LayoutKey` asks the texts below it to publish their layout: they are measured only then.
@MainActor func _notePreferenceReader<K: PreferenceKey>(_ key: K.Type, in context: inout _RenderContext) {
  if _storedTypeID(K.self) == _storedTypeID(Text.LayoutKey.self) {
    Text._installMeasuredRendering()
    context.environment._publishesTextLayout = true
  }
}

/// Measures `node`'s frame in the window: the host sends it as `geometryChange` after commits, on resize and as an
/// ancestor scrolls. A new frame is kept under `key` and renders the owner again, and `reader`, the owner of the layer an
/// anchor made from the frame is drawn in (it is above the owner, and a render of the owner alone would leave it as it was).
@MainActor func _measureWindowFrame(of node: _RenderNode, key: String, store: StateStore, owner: UInt64?, reader: UInt64? = nil) {
  let depth = Int(node.attributes["data-geometry-change"] ?? "") ?? 0
  node.attributes["data-geometry-change"] = String(depth + 1)
  node.attributes["data-geometry-change-position"] = "true"
  let previous = node.events["geometryChange"]?.valueAction
  node.events["geometryChange"] = _EventHandler(name: "geometryChange", action: { raw in
    previous?(raw)
    guard let measurement = _GeometryMeasurement(decoding: raw) else { return }
    // Where the view's corner is in the window, with the size it lays out at (see `_GeometryMeasurement.anchorFrame`), and
    // where its axes go when a transform is above it: an anchor made here is read through the window by a view that may be
    // under another.
    let space = measurement.anchorSpace, size = measurement.size
    let frame = CGRect(x: space.origin.x, y: space.origin.y, width: size.width, height: size.height)
    let axes = space.a == 1 && space.b == 0 && space.c == 0 && space.d == 1 ? nil : CGRect(x: space.a, y: space.b, width: space.c, height: space.d)
    guard store._windowFrames[key] != frame || store._windowFrames[key + "#axes"] != axes else { return }
    store._windowFrames[key] = frame
    store._windowFrames[key + "#axes"] = axes
    if let owner { store._ownerObservationDidChange(owner) }
    if let reader, reader != owner { store._ownerObservationDidChange(reader) }
  })
}

/// The frame an anchor is made from, as `_measureWindowFrame` last stored it for `key` (zero before the first measurement).
@MainActor func _anchorFrame(key: String, store: StateStore) -> _AnchorFrame {
  let frame = store._windowFrames[key] ?? CGRect(x: 0, y: 0, width: 0, height: 0)
  var space = _AnchorSpace(origin: frame.origin)
  if let axes = store._windowFrames[key + "#axes"] { space.a = axes.origin.x; space.b = axes.origin.y; space.c = axes.size.width; space.d = axes.size.height }
  return _AnchorFrame(space: space, size: frame.size)
}

private struct _PublishesTextLayoutKey: EnvironmentKey {
  static var defaultValue: Bool { false }
}

extension EnvironmentValues {
  /// Whether a reader of `Text.LayoutKey` above wants the texts here to publish their layout.
  var _publishesTextLayout: Bool {
    get { self[_PublishesTextLayoutKey.self] }
    set { self[_PublishesTextLayoutKey.self] = newValue }
  }
}

// MARK: Text layout preference

extension Text {
  /// The preference a text gives the views above: its layout, with an anchor of where its origin is.
  public struct LayoutKey: PreferenceKey {
    /// A text's layout and the origin of its coordinates.
    public struct AnchoredLayout: Equatable {
      public var origin: Anchor<CGPoint>
      public var layout: Text.Layout

      public static func == (a: Text.LayoutKey.AnchoredLayout, b: Text.LayoutKey.AnchoredLayout) -> Bool {
        a.origin == b.origin && a.layout == b.layout
      }
    }

    public typealias Value = [Text.LayoutKey.AnchoredLayout]

    public static var defaultValue: Text.LayoutKey.Value { [] }

    public static func reduce(value: inout Text.LayoutKey.Value, nextValue: () -> Text.LayoutKey.Value) {
      value.append(contentsOf: nextValue())
    }
  }
}

extension Text.LayoutKey: Sendable {}
