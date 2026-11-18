
// MARK: - Animation compatibility used by Layout

/// A small, backend-neutral equivalent of SwiftUI's `VectorArithmetic`.
/// Layouts inherit `Animatable` in SwiftUI, so keeping these protocols in the
/// core module lets third-party layouts use the same source shape without
/// importing a browser animation type.
public protocol VectorArithmetic: AdditiveArithmetic {
  var magnitudeSquared: Double { get }
  mutating func scale(by rhs: Double)
}

public struct EmptyAnimatableData: VectorArithmetic, Sendable {
  public init() {}
  public static var zero: EmptyAnimatableData { EmptyAnimatableData() }
  public static func + (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { EmptyAnimatableData() }
  public static func - (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { EmptyAnimatableData() }
  public var magnitudeSquared: Double { 0 }
  public mutating func scale(by rhs: Double) {}
}

extension Double: VectorArithmetic {
  public var magnitudeSquared: Double { self * self }
  public mutating func scale(by rhs: Double) { self *= rhs }
}

// Platform geometry uses the real CGFloat on native targets
// platforms. Only the Foundation-free/Embedded branch aliases it to Double.

public protocol Animatable {
  associatedtype AnimatableData: VectorArithmetic = EmptyAnimatableData
  var animatableData: AnimatableData { get set }
  /// Whether the type has data to animate; false for `EmptyAnimatableData` (`Animator.swift`).
  static var _swiftUIWebAnimates: Bool { get }
}

public extension Animatable where AnimatableData == EmptyAnimatableData {
  var animatableData: EmptyAnimatableData {
    get { EmptyAnimatableData() }
    set {}
  }
}

/// Renderer-owned cache storage. A single store is shared by all descendants
/// of a `FiberTree`, allowing value-type layouts to retain their cache across
/// body updates while still replacing it when `AnyLayout` changes algorithm.
@_spi(Renderer) public final class _LayoutCacheStore {
  private struct Entry {
    let identifier: String
    let value: Any
  }
  private var entries: [String: Entry] = .init()

  public init() {}

  @_spi(Renderer) public func value(for key: String, identifier: String) -> Any? {
    guard let entry = entries[key], entry.identifier == identifier else { return nil }
    return entry.value
  }

  @_spi(Renderer) public func setValue(_ value: Any, for key: String, identifier: String) {
    if entries[key] == nil, entries.count >= 2048, let evicted = entries.keys.first {
      entries.removeValue(forKey: evicted)
    }
    entries[key] = Entry(identifier: identifier, value: value)
  }

  @_spi(Renderer) public func removeAll() { entries.removeAll(keepingCapacity: true) }
}

// MARK: - SwiftUI-compatible layout values

/// A size proposed by a parent layout. `nil` means that the dimension is
/// unspecified; the layout child is free to choose its ideal size.
public struct ProposedViewSize: Equatable, Sendable {
  public var width: CGFloat?
  public var height: CGFloat?

  public init(width: CGFloat?, height: CGFloat?) {
    self.width = width
    self.height = height
  }

  public init(_ size: CGSize) {
    self.init(width: size.width, height: size.height)
  }

  public static let zero = ProposedViewSize(width: 0, height: 0)
  public static let unspecified = ProposedViewSize(width: nil, height: nil)
  public static let infinity = ProposedViewSize(width: .infinity, height: .infinity)

  public func replacingUnspecifiedDimensions(by size: CGSize = _SwiftUIWebGeometryDefaults.defaultUnspecifiedSize) -> CGSize {
    CGSize(width: width ?? size.width, height: height ?? size.height)
  }
}

/// Renderer-owned persistence for split-view divider positions. Values are
/// normalized fractions (one per content column) rather than pixels, which
/// keeps a user's split stable when the browser viewport changes size.
@_spi(Renderer) public final class _SplitViewStateStore {
  private var values: [String: [Double]] = .init()

  public init() {}

  @_spi(Renderer) public func value(for key: String) -> [Double]? {
    values[key]
  }

  @_spi(Renderer) public func setValue(_ value: [Double], for key: String) {
    values[key] = value.map { min(1, max(0, $0)) }
  }

  @_spi(Renderer) public func removeValue(for key: String) {
    values.removeValue(forKey: key)
  }
}

/// The edges contributed by a child to default stack spacing.
public struct ViewSpacing: Sendable {
  private var topValue: CGFloat
  private var leadingValue: CGFloat
  private var bottomValue: CGFloat
  private var trailingValue: CGFloat

  public init() {
    topValue = 0; leadingValue = 0; bottomValue = 0; trailingValue = 0
  }

  fileprivate init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
    topValue = top; leadingValue = leading; bottomValue = bottom; trailingValue = trailing
  }

  public static let zero = ViewSpacing()

  public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) {
    if edges.contains(.top) { topValue = max(topValue, other.topValue) }
    if edges.contains(.leading) { leadingValue = max(leadingValue, other.leadingValue) }
    if edges.contains(.bottom) { bottomValue = max(bottomValue, other.bottomValue) }
    if edges.contains(.trailing) { trailingValue = max(trailingValue, other.trailingValue) }
  }

  public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing {
    var result = self
    result.formUnion(other, edges: edges)
    return result
  }

  public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat {
    switch axis {
    case .horizontal: return max(0, trailingValue + next.leadingValue)
    case .vertical: return max(0, bottomValue + next.topValue)
    }
  }

  fileprivate static let system = ViewSpacing(top: 4, leading: 4, bottom: 4, trailing: 4)
  package var _top: CGFloat { topValue }
  package var _leading: CGFloat { leadingValue }
  package var _bottom: CGFloat { bottomValue }
  package var _trailing: CGFloat { trailingValue }
}

/// Alignment values exposed to custom layouts. The common SwiftUI guides and
/// custom `AlignmentID` values are resolved by `ViewDimensions`.
public struct ViewDimensions {
  package let size: CGSize
  private let overrides: [String: CGFloat]
  private let explicitHorizontal: ((HorizontalAlignment) -> CGFloat?)?
  private let explicitVertical: ((VerticalAlignment) -> CGFloat?)?

  package init(size: CGSize) {
    self.size = size
    overrides = .init()
    explicitHorizontal = nil
    explicitVertical = nil
  }
  fileprivate init(
    size: CGSize,
    overrides: [String: CGFloat],
    explicitHorizontal: ((HorizontalAlignment) -> CGFloat?)? = nil,
    explicitVertical: ((VerticalAlignment) -> CGFloat?)? = nil
  ) {
    self.size = size
    self.overrides = overrides
    self.explicitHorizontal = explicitHorizontal
    self.explicitVertical = explicitVertical
  }
  public var width: CGFloat { size.width }
  public var height: CGFloat { size.height }

  public subscript(_ guide: HorizontalAlignment) -> CGFloat {
    if let value = overrides[guide.cssValue] { return value }
    if let value = explicitHorizontal?(guide) { return value }
    return guide._defaultValue(in: self)
  }

  public subscript(_ guide: VerticalAlignment) -> CGFloat {
    if let value = overrides[guide.cssValue] { return value }
    if let value = explicitVertical?(guide) { return value }
    return guide._defaultValue(in: self)
  }
}

public struct LayoutProperties: Sendable {
  public init() { stackOrientation = nil }
  public var stackOrientation: Axis?
}

public protocol LayoutValueKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

// MARK: - LayoutSubview and LayoutSubviews

package struct _LayoutPlacement {
  package var point: CGPoint
  package var anchor: UnitPoint
  package var proposal: ProposedViewSize
}

package final class _LayoutSubviewStorage {
  let node: _RenderNode
  let id: Int
  var lastSize: CGSize
  var lastProposal: ProposedViewSize?
  var placement: _LayoutPlacement?
  var renderedNode: _RenderNode?
  /// What the host measured for this subview, with the proposal it measured each size under: the one the subview was placed
  /// with and the others the layout asked its size at.
  package var hostSizes: [(proposal: ProposedViewSize, size: CGSize)] = []
  /// The proposals the layout asked this subview's size at, in the order it first asked them (the host measures them).
  package var asked: [ProposedViewSize] = []

  package init(node: _RenderNode, id: Int, initialSize: CGSize) {
    self.node = node; self.id = id; lastSize = initialSize; lastProposal = nil; renderedNode = nil
  }
}

/// A value set by `layoutValue(key:value:)`, as the render node keeps it. Embedded Swift cannot cast `Any` back to
/// the key's value type, so the value travels in a class box that `LayoutSubview` downcasts by the key's type.
@_spi(Renderer) public final class _LayoutValueBox<Value> {
  public let value: Value
  public init(_ value: Value) { self.value = value }
}

public struct LayoutSubview: Equatable {
  fileprivate let storage: _LayoutSubviewStorage

  package init(storage: _LayoutSubviewStorage) { self.storage = storage }

  public var priority: Double {
    if let value = storage.node.attributes["data-layout-priority"], let priority = Double(value) { return priority }
    return 0
  }

  public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
    guard let box = storage.node._layoutValues[ObjectIdentifier(key)] else { return K.defaultValue }
    // The key's type identifies the box's value type, so the downcast cannot be wrong.
    return unsafeDowncast(box, to: _LayoutValueBox<K.Value>.self).value
  }

  public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    if !storage.asked.contains(proposal) { storage.asked.append(proposal) }
    if storage.lastProposal == proposal { return storage.lastSize }
    // The host measured this subview's real content for exactly this proposal.
    if let host = storage.hostSizes.first(where: { $0.proposal == proposal }) {
      storage.lastSize = host.size
      storage.lastProposal = proposal
      return host.size
    }
    let target = storage.node._layoutRender?(proposal) ?? storage.node
    storage.renderedNode = target
    let result = _LayoutNodeMeasurer.measure(target, proposal: proposal, resolveLayoutBoundary: false)
    storage.lastSize = result
    storage.lastProposal = proposal
    return result
  }

  public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
    let measured = sizeThatFits(proposal)
    let base = ViewDimensions(size: measured)
    let target = storage.renderedNode ?? storage.node
    let overrides = target._layoutAlignmentGuides.mapValues { $0(base) }
    // A nested custom Layout may expose an explicit alignment for a custom
    // `AlignmentID`. Ask its resolver lazily for the guide requested by the
    // enclosing layout; child `.alignmentGuide` values remain authoritative
    // when present in the eagerly computed overrides above.
    return ViewDimensions(
      size: measured,
      overrides: overrides,
      explicitHorizontal: target._layoutExplicitHorizontalAlignment,
      explicitVertical: target._layoutExplicitVerticalAlignment
    )
  }

  public var spacing: ViewSpacing {
    _LayoutNodeMeasurer.spacing(for: storage.node)
  }

  public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
    _ = sizeThatFits(proposal)
    storage.placement = _LayoutPlacement(point: position, anchor: anchor, proposal: proposal)
  }

  public static func == (lhs: LayoutSubview, rhs: LayoutSubview) -> Bool {
    lhs.storage.id == rhs.storage.id
  }

  fileprivate var _isFlexible: Bool {
    storage.node.classes.contains("flex-spacer") || storage.node.styles["flex-grow"] == "1"
  }
  fileprivate var _flexesHorizontally: Bool { _isFlexible || storage.node.styles["width"] == "100%" }
  fileprivate var _flexesVertically: Bool { _isFlexible || storage.node.styles["height"] == "100%" }
  fileprivate var _allocatesHorizontally: Bool { _flexesHorizontally || priority > 0 }
  fileprivate var _allocatesVertically: Bool { _flexesVertically || priority > 0 }
  fileprivate var _isFixedHorizontally: Bool {
    storage.node.styles["width"].map { _trimLayoutString($0) == "max-content" } == true ||
      storage.node.styles["min-width"].map { _trimLayoutString($0) == "max-content" } == true
  }
  fileprivate var _isFixedVertically: Bool {
    storage.node.styles["height"].map { _trimLayoutString($0) == "max-content" } == true ||
      storage.node.styles["min-height"].map { _trimLayoutString($0) == "max-content" } == true
  }
  fileprivate var _isGridRow: Bool { storage.node.classes.contains("grid-row") }

  package var _size: CGSize { storage.lastSize }
  package var _placement: _LayoutPlacement? { storage.placement }
  package var _renderedNode: _RenderNode? { storage.renderedNode }
  /// The proposals the layout asked this subview's size at besides the one it placed it with, which the host measures too.
  package var _askedProposals: [ProposedViewSize] { storage.asked.filter { $0 != storage.placement?.proposal } }
  /// Renderer-facing source node used by internal layouts that need semantic
  /// metadata (for example split divider markers) without exposing storage to
  /// application code.
  @_spi(Renderer) public var _node: _RenderNode { storage.node }
}

public struct LayoutSubviews: RandomAccessCollection, Equatable {
  public typealias Element = LayoutSubview
  public typealias Index = Int
  private let values: [LayoutSubview]

  package init(_ values: [LayoutSubview]) { self.values = values }
  public var startIndex: Int { values.startIndex }
  public var endIndex: Int { values.endIndex }
  public subscript(index: Int) -> LayoutSubview { values[index] }

  public static func == (lhs: LayoutSubviews, rhs: LayoutSubviews) -> Bool { lhs.values == rhs.values }
}

// MARK: - Layout protocol and type erasure

@preconcurrency public protocol Layout: Animatable {
  associatedtype Cache = ()
  typealias Subviews = LayoutSubviews

  static var layoutProperties: LayoutProperties { get }
  /// Package hooks: built-in layouts implement these, and the public requirements forward to them,
  /// so their concrete types expose only SwiftUI's members.
  static var _builtInLayoutProperties: LayoutProperties { get }
  func _builtInSizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize
  func _builtInPlaceSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache)
  /// Static renderer metadata avoids runtime type casts in Embedded Swift.
  var _swiftUIWebSemanticLayout: _NodeValues? { get }
  var _swiftUIWebSplitAxisRaw: String? { get }
  var _swiftUIWebSplitDividerThickness: CGFloat { get }
  func makeCache(subviews: Self.Subviews) -> Self.Cache
  func updateCache(_ cache: inout Self.Cache, subviews: Self.Subviews)
  func spacing(subviews: Self.Subviews, cache: inout Self.Cache) -> ViewSpacing
  func sizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache)
  func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat?
  func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat?
}

public extension Layout {
  static var layoutProperties: LayoutProperties { _builtInLayoutProperties }
  /// Custom layouts implement these; built-in layouts reach them through the package hooks.
  func sizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize {
    _builtInSizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) {
    _builtInPlaceSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
  }
  var _swiftUIWebSemanticLayout: _NodeValues? { nil }
  var _swiftUIWebSplitAxisRaw: String? { nil }
  var _swiftUIWebSplitDividerThickness: CGFloat { 0 }
  func updateCache(_ cache: inout Self.Cache, subviews: Self.Subviews) {}
  func spacing(subviews: Self.Subviews, cache: inout Self.Cache) -> ViewSpacing { .zero }
  func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat? { nil }
  func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat? { nil }

}

public extension Layout {
  static var _builtInLayoutProperties: LayoutProperties { LayoutProperties() }
  func _builtInSizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize { .zero }
  func _builtInPlaceSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) {}
}

public extension Layout where Cache == () {
  func makeCache(subviews: Self.Subviews) -> Self.Cache { () }
}

private final class _AnyLayoutCacheBox<L: Layout> {
  var layout: L
  var cache: L.Cache
  init(layout: L, cache: L.Cache) { self.layout = layout; self.cache = cache }
}

#if hasFeature(Embedded)
private final class _EmbeddedAnyLayoutCacheBox<L: Layout> {
  var layout: L
  var cache: L.Cache?
  init(layout: L) { self.layout = layout; self.cache = nil }
}
#endif

package struct _GridLayoutConfiguration {
  package let alignment: Alignment
  package let horizontalSpacing: CGFloat
  let verticalSpacing: CGFloat
  package init(alignment: Alignment, horizontalSpacing: CGFloat, verticalSpacing: CGFloat) {
    self.alignment = alignment
    self.horizontalSpacing = horizontalSpacing
    self.verticalSpacing = verticalSpacing
  }
}

public struct AnyLayout: Layout {
  public struct Cache {
    fileprivate var storage: Any?
    init() { storage = nil }
    fileprivate init(storage: Any?) { self.storage = storage }
  }
  public let _swiftUIWebSemanticLayout: _NodeValues?
  private let identifier: String
  private let makeClosure: (LayoutSubviews) -> Cache
  private let updateClosure: (inout Cache, LayoutSubviews) -> Void
  private let spacingClosure: (LayoutSubviews, inout Cache) -> ViewSpacing
  private let sizeClosure: (ProposedViewSize, LayoutSubviews, inout Cache) -> CGSize
  private let placeClosure: (CGRect, ProposedViewSize, LayoutSubviews, inout Cache) -> Void
  private let horizontalAlignmentClosure: (HorizontalAlignment, CGRect, ProposedViewSize, LayoutSubviews, inout Cache) -> CGFloat?
  private let verticalAlignmentClosure: (VerticalAlignment, CGRect, ProposedViewSize, LayoutSubviews, inout Cache) -> CGFloat?
  private let animatableDescription: String
  private let gridConfiguration: _GridLayoutConfiguration?

  public init<L: Layout>(_ layout: L) {
    _swiftUIWebSemanticLayout = layout._swiftUIWebSemanticLayout
    identifier = _swiftUIWebTypeName(L.self)
    animatableDescription = _swiftUIWebDescribe(layout.animatableData)
    #if hasFeature(Embedded)
    gridConfiguration = nil
    // Keep a typed reference box captured directly by the erased operations.
    // This provides AnyLayout semantics without `Any` downcasts, which the
    // Embedded runtime deliberately does not implement.
    let box = _EmbeddedAnyLayoutCacheBox(layout: layout)
    makeClosure = { subviews in
      box.layout = layout
      box.cache = layout.makeCache(subviews: subviews)
      return Cache()
    }
    updateClosure = { _, subviews in
      box.layout = layout
      guard var typed = box.cache else { return }
      box.layout.updateCache(&typed, subviews: subviews)
      box.cache = typed
    }
    spacingClosure = { subviews, _ in
      guard var typed = box.cache else { return .zero }
      let result = box.layout.spacing(subviews: subviews, cache: &typed); box.cache = typed; return result
    }
    sizeClosure = { proposal, subviews, _ in
      guard var typed = box.cache else { return .zero }
      let result = box.layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &typed); box.cache = typed; return result
    }
    placeClosure = { bounds, proposal, subviews, _ in
      guard var typed = box.cache else { return }
      box.layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &typed); box.cache = typed
    }
    horizontalAlignmentClosure = { guide, bounds, proposal, subviews, _ in
      guard var typed = box.cache else { return nil }
      let result = box.layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &typed); box.cache = typed; return result
    }
    verticalAlignmentClosure = { guide, bounds, proposal, subviews, _ in
      guard var typed = box.cache else { return nil }
      let result = box.layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &typed); box.cache = typed; return result
    }
    #else
    gridConfiguration = (layout as? GridLayout).map {
      _GridLayoutConfiguration(
        alignment: $0.alignment,
        horizontalSpacing: $0.horizontalSpacing ?? 8,
        verticalSpacing: $0.verticalSpacing ?? 8
      )
    }
    makeClosure = { subviews in
      Cache(storage: _AnyLayoutCacheBox(layout: layout, cache: layout.makeCache(subviews: subviews)))
    }
    updateClosure = { cache, subviews in
      guard let box = cache.storage as? _AnyLayoutCacheBox<L> else { return }
      box.layout = layout
      box.layout.updateCache(&box.cache, subviews: subviews)
    }
    spacingClosure = { subviews, cache in
      guard let box = cache.storage as? _AnyLayoutCacheBox<L> else { return .zero }
      return box.layout.spacing(subviews: subviews, cache: &box.cache)
    }
    sizeClosure = { proposal, subviews, cache in
      guard let box = cache.storage as? _AnyLayoutCacheBox<L> else { return CGSize(width: 0, height: 0) }
      return box.layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &box.cache)
    }
    placeClosure = { bounds, proposal, subviews, cache in
      guard let box = cache.storage as? _AnyLayoutCacheBox<L> else { return }
      box.layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &box.cache)
    }
    horizontalAlignmentClosure = { guide, bounds, proposal, subviews, cache in
      guard let box = cache.storage as? _AnyLayoutCacheBox<L> else { return nil }
      return box.layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &box.cache)
    }
    verticalAlignmentClosure = { guide, bounds, proposal, subviews, cache in
      guard let box = cache.storage as? _AnyLayoutCacheBox<L> else { return nil }
      return box.layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &box.cache)
    }
    #endif
  }

  public static var _builtInLayoutProperties: LayoutProperties { LayoutProperties() }
  public func makeCache(subviews: AnyLayout.Subviews) -> AnyLayout.Cache { makeClosure(subviews) }
  public func updateCache(_ cache: inout AnyLayout.Cache, subviews: AnyLayout.Subviews) { updateClosure(&cache, subviews) }
  public func spacing(subviews: AnyLayout.Subviews, cache: inout AnyLayout.Cache) -> ViewSpacing { spacingClosure(subviews, &cache) }
  public func sizeThatFits(proposal: ProposedViewSize, subviews: AnyLayout.Subviews, cache: inout AnyLayout.Cache) -> CGSize { sizeClosure(proposal, subviews, &cache) }
  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: AnyLayout.Subviews, cache: inout AnyLayout.Cache) { placeClosure(bounds, proposal, subviews, &cache) }
  public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: AnyLayout.Subviews, cache: inout AnyLayout.Cache) -> CGFloat? { horizontalAlignmentClosure(guide, bounds, proposal, subviews, &cache) }
  public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: AnyLayout.Subviews, cache: inout AnyLayout.Cache) -> CGFloat? { verticalAlignmentClosure(guide, bounds, proposal, subviews, &cache) }
  fileprivate var _identifier: String { identifier }
  package var _animatableDescription: String { animatableDescription }
  package var _gridConfiguration: _GridLayoutConfiguration? { gridConfiguration }
}

// MARK: - Built-in layout algorithms

public struct HStackLayout: Layout {
  public var _swiftUIWebSemanticLayout: _NodeValues? {
    var attributes = _semanticAlignment(Alignment(horizontal: .center, vertical: alignment))
    attributes["data-layout-kind"] = "hstack"
    attributes["data-layout-gap"] = _semanticNumber(Double(spacing ?? 8))
    return attributes
  }
  public typealias Cache = ()
  public var spacing: CGFloat?
  public var alignment: VerticalAlignment
  public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
    self.alignment = alignment; self.spacing = spacing
  }
  public static var _builtInLayoutProperties: LayoutProperties { var p = LayoutProperties(); p.stackOrientation = .horizontal; return p }

  public func _builtInSizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height)) }
    let gaps = _stackGaps(subviews, axis: .horizontal, explicit: spacing)
    let fixed = sizes.reduce(0) { $0 + $1.width } + gaps.reduce(0, +)
    let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
    // A non-zero layout priority affects compression order, not intrinsic
    // expansion. Only a Spacer/100%-sized child asks the stack to consume
    // otherwise-unused proposal space.
    let hasFlexible = subviews.contains(where: { $0._flexesHorizontally })
    let width: CGFloat
    if let proposedWidth {
      width = hasFlexible ? max(fixed, proposedWidth) : min(fixed, proposedWidth)
    } else {
      width = fixed
    }
    let height = sizes.map { $0.height }.max() ?? 0
    return CGSize(width: width, height: proposal.height.map { min($0, height) } ?? height)
  }

  public func _builtInPlaceSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) {
    let initial = subviews.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height)) }
    let gaps = _stackGaps(subviews, axis: .horizontal, explicit: spacing)
    let flexibleIndices = subviews.indices.filter { subviews[$0]._allocatesHorizontally }
    let idealWidth = initial.reduce(0) { $0 + $1.width } + gaps.reduce(0, +)
    var allocated = initial.map { $0.width }
    let availableWidth = max(0, bounds.size.width - gaps.reduce(0, +))
    if idealWidth > bounds.size.width {
      // Compression follows SwiftUI's priority rule: lower-priority views
      // yield their ideal width before higher-priority views do. The minimum
      // proposal is intentionally `.zero`, matching ordinary Text/Shape
      // behavior while preserving explicit frame minimums in measurement.
      var remaining = idealWidth - bounds.size.width
      let priorities = Array(Set(subviews.map { $0.priority })).sorted()
      for priority in priorities where remaining > 0 {
        let indices = subviews.indices.filter { subviews[$0].priority == priority && !subviews[$0]._isFixedHorizontally }
        let capacity = indices.reduce(0) { $0 + allocated[$1] }
        let shrink = min(capacity, remaining)
        if capacity > 0 {
          for index in indices { allocated[index] -= shrink * allocated[index] / capacity }
        }
        remaining -= shrink
      }
    } else if !flexibleIndices.isEmpty {
      let fixedIdeal = initial.enumerated().reduce(0) { result, item in result + (subviews[item.offset]._allocatesHorizontally ? 0 : item.element.width) }
      let extraWidth = max(0, availableWidth - fixedIdeal)
      let totalWeight = flexibleIndices.reduce(0) { result, index in
        result + (subviews[index].priority > 0 ? subviews[index].priority : 1)
      }
      if totalWeight > 0 {
        for index in flexibleIndices {
          let weight = subviews[index].priority > 0 ? subviews[index].priority : 1
          allocated[index] = extraWidth * CGFloat(weight / totalWeight)
        }
      }
    }
    let baselineGuide: CGFloat? = (alignment == .firstTextBaseline || alignment == .lastTextBaseline)
      ? subviews.indices.map { subviews[$0].dimensions(in: ProposedViewSize(width: initial[$0].width, height: initial[$0].height))[alignment] }.max()
      : nil
    let customGuide: CGFloat? = (alignment != .top && alignment != .center && alignment != .bottom &&
                                 alignment != .firstTextBaseline && alignment != .lastTextBaseline)
      ? subviews.indices.map { subviews[$0].dimensions(in: ProposedViewSize(width: initial[$0].width, height: initial[$0].height))[alignment] }.max()
      : nil
    var x = bounds.origin.x
    for index in subviews.indices {
      let child = subviews[index]
      let width = allocated[index]
      let size = CGSize(width: width, height: initial[index].height)
      let y: CGFloat
      if let baselineGuide {
        let childBaseline = child.dimensions(in: ProposedViewSize(width: width, height: size.height))[alignment]
        y = bounds.origin.y + baselineGuide - childBaseline
      } else if let customGuide {
        let childGuide = child.dimensions(in: ProposedViewSize(width: width, height: size.height))[alignment]
        y = bounds.origin.y + customGuide - childGuide
      } else {
        y = bounds.origin.y + _crossOffset(container: bounds.size.height, child: size.height, alignment: alignment)
      }
      child.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: size.height))
      x += width + (index < gaps.count ? gaps[index] : 0)
    }
  }
}

public struct VStackLayout: Layout {
  public var _swiftUIWebSemanticLayout: _NodeValues? {
    var attributes = _semanticAlignment(Alignment(horizontal: alignment, vertical: .center))
    attributes["data-layout-kind"] = "vstack"
    attributes["data-layout-gap"] = _semanticNumber(Double(spacing ?? 8))
    return attributes
  }
  public typealias Cache = ()
  public var spacing: CGFloat?
  public var alignment: HorizontalAlignment
  public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
    self.alignment = alignment; self.spacing = spacing
  }
  public static var _builtInLayoutProperties: LayoutProperties { var p = LayoutProperties(); p.stackOrientation = .vertical; return p }

  public func _builtInSizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
    let gaps = _stackGaps(subviews, axis: .vertical, explicit: spacing)
    let width = sizes.map { $0.width }.max() ?? 0
    let fixed = sizes.reduce(0) { $0 + $1.height } + gaps.reduce(0, +)
    let proposedHeight = proposal.height.flatMap { $0.isFinite ? $0 : nil }
    let hasFlexible = subviews.contains(where: { $0._flexesVertically })
    let height: CGFloat
    if let proposedHeight {
      height = hasFlexible ? max(fixed, proposedHeight) : min(fixed, proposedHeight)
    } else {
      height = fixed
    }
    return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
  }

  public func _builtInPlaceSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) {
    let initial = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
    let gaps = _stackGaps(subviews, axis: .vertical, explicit: spacing)
    let flexibleIndices = subviews.indices.filter { subviews[$0]._allocatesVertically }
    let idealHeight = initial.reduce(0) { $0 + $1.height } + gaps.reduce(0, +)
    var allocated = initial.map { $0.height }
    let availableHeight = max(0, bounds.size.height - gaps.reduce(0, +))
    if idealHeight > bounds.size.height {
      var remaining = idealHeight - bounds.size.height
      let priorities = Array(Set(subviews.map { $0.priority })).sorted()
      for priority in priorities where remaining > 0 {
        let indices = subviews.indices.filter { subviews[$0].priority == priority && !subviews[$0]._isFixedVertically }
        let capacity = indices.reduce(0) { $0 + allocated[$1] }
        let shrink = min(capacity, remaining)
        if capacity > 0 {
          for index in indices { allocated[index] -= shrink * allocated[index] / capacity }
        }
        remaining -= shrink
      }
    } else if !flexibleIndices.isEmpty {
      let fixedIdeal = initial.enumerated().reduce(0) { result, item in result + (subviews[item.offset]._allocatesVertically ? 0 : item.element.height) }
      let extraHeight = max(0, availableHeight - fixedIdeal)
      let totalWeight = flexibleIndices.reduce(0) { result, index in
        result + (subviews[index].priority > 0 ? subviews[index].priority : 1)
      }
      if totalWeight > 0 {
        for index in flexibleIndices {
          let weight = subviews[index].priority > 0 ? subviews[index].priority : 1
          allocated[index] = extraHeight * CGFloat(weight / totalWeight)
        }
      }
    }
    let customGuide: CGFloat? = (alignment != .leading && alignment != .center && alignment != .trailing)
      ? subviews.indices.map { subviews[$0].dimensions(in: ProposedViewSize(width: initial[$0].width, height: initial[$0].height))[alignment] }.max()
      : nil
    var y = bounds.origin.y
    for index in subviews.indices {
      let child = subviews[index]
      let height = allocated[index]
      let size = CGSize(width: initial[index].width, height: height)
      let x: CGFloat
      if let customGuide {
        let childGuide = child.dimensions(in: ProposedViewSize(width: size.width, height: height))[alignment]
        x = bounds.origin.x + customGuide - childGuide
      } else if alignment == .leading || alignment == .trailing {
        let guide = child.dimensions(in: ProposedViewSize(width: size.width, height: height))[alignment]
        x = alignment == .leading ? bounds.origin.x - guide : bounds.origin.x + bounds.size.width - guide
      } else {
        x = bounds.origin.x + _crossOffset(container: bounds.size.width, child: size.width, alignment: alignment)
      }
      child.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: height))
      y += height + (index < gaps.count ? gaps[index] : 0)
    }
  }
}

public struct ZStackLayout: Layout {
  public var _swiftUIWebSemanticLayout: _NodeValues? {
    var attributes = _semanticAlignment(alignment)
    attributes["data-layout-kind"] = "zstack"
    return attributes
  }
  public typealias Cache = ()
  public var alignment: Alignment
  public init(alignment: Alignment = .center) { self.alignment = alignment }

  public func _builtInSizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(proposal) }
    let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
    let proposedHeight = proposal.height.flatMap { $0.isFinite ? $0 : nil }
    return CGSize(width: proposedWidth ?? sizes.map { $0.width }.max() ?? 0, height: proposedHeight ?? sizes.map { $0.height }.max() ?? 0)
  }

  public func _builtInPlaceSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) {
    for child in subviews {
      let size = child.sizeThatFits(proposal)
      let dimensions = child.dimensions(in: ProposedViewSize(width: size.width, height: size.height))
      let x: CGFloat
      if let guide = alignment._horizontalGuide {
        x = bounds.origin.x + bounds.size.width / 2 - dimensions[guide]
      } else {
        x = bounds.origin.x + _crossOffset(container: bounds.size.width, child: size.width, alignment: alignment.horizontalValue)
      }
      let y: CGFloat
      if let guide = alignment._verticalGuide {
        y = bounds.origin.y + bounds.size.height / 2 - dimensions[guide]
      } else {
        y = bounds.origin.y + _crossOffset(container: bounds.size.height, child: size.height, alignment: alignment.verticalValue)
      }
      child.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
    }
  }
}

public nonisolated struct GridLayout: Layout {
  public typealias Cache = ()
  public var alignment: Alignment
  public var horizontalSpacing: CGFloat?
  public var verticalSpacing: CGFloat?
  public nonisolated init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil) {
    self.alignment = alignment; self.horizontalSpacing = horizontalSpacing; self.verticalSpacing = verticalSpacing
  }

  public func _builtInSizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize {
    if !subviews.isEmpty && subviews.allSatisfy({ $0._isGridRow }) {
      let hGap = horizontalSpacing ?? 8
      let columnWidths = _gridColumnWidths(subviews.map { $0.storage.node }, hGap)
      let contentWidth = columnWidths.reduce(0, +) + Double(max(0, columnWidths.count - 1)) * Double(hGap)
      let rowSizes = subviews.map { _gridRowContentSize($0.storage.node, hGap, columnWidths: columnWidths) }
      let vGap = verticalSpacing ?? 8
      let measuredWidth = contentWidth
      let measuredHeight = rowSizes.reduce(0) { $0 + $1.height } + CGFloat(max(0, rowSizes.count - 1)) * vGap
      let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? measuredWidth
      let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? measuredHeight
      return CGSize(width: width, height: height)
    }
    let columns = max(1, Int(Double(max(1, subviews.count)).squareRoot().rounded(.up)))
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let columnWidths = (0..<columns).map { column in sizes.enumerated().filter { $0.offset % columns == column }.map { $0.element.width }.max() ?? 0 }
    let rowCount = (subviews.count + columns - 1) / columns
    let rowHeights = (0..<rowCount).map { row in sizes.enumerated().filter { $0.offset / columns == row }.map { $0.element.height }.max() ?? 0 }
    let hGap = horizontalSpacing ?? 8
    let vGap = verticalSpacing ?? 8
    let width = columnWidths.reduce(0, +) + CGFloat(max(0, columns - 1)) * hGap
    let height = rowHeights.reduce(0, +) + CGFloat(max(0, rowCount - 1)) * vGap
    let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
    let proposedHeight = proposal.height.flatMap { $0.isFinite ? $0 : nil }
    return CGSize(width: proposedWidth ?? width, height: proposedHeight ?? height)
  }

  public func _builtInPlaceSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) {
    if !subviews.isEmpty && subviews.allSatisfy({ $0._isGridRow }) {
      let hGap = horizontalSpacing ?? 8
      let columnWidths = _gridColumnWidths(subviews.map { $0.storage.node }, hGap)
      let contentWidth = columnWidths.reduce(0, +) + Double(max(0, columnWidths.count - 1)) * Double(hGap)
      let rowSizes = subviews.map { _gridRowContentSize($0.storage.node, hGap, columnWidths: columnWidths) }
      let vGap = verticalSpacing ?? 8
      var y = bounds.origin.y
      for index in subviews.indices {
        let rowSize = rowSizes[index]
        let x = bounds.origin.x + _crossOffset(container: CGFloat(bounds.size.width), child: CGFloat(contentWidth), alignment: alignment.horizontalValue)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: contentWidth, height: rowSize.height))
        y += rowSize.height + vGap
      }
      return
    }
    let columns = max(1, Int(Double(max(1, subviews.count)).squareRoot().rounded(.up)))
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let columnWidths = (0..<columns).map { column in sizes.enumerated().filter { $0.offset % columns == column }.map { $0.element.width }.max() ?? 0 }
    let rowCount = (subviews.count + columns - 1) / columns
    let rowHeights = (0..<rowCount).map { row in sizes.enumerated().filter { $0.offset / columns == row }.map { $0.element.height }.max() ?? 0 }
    let hGap = horizontalSpacing ?? 8; let vGap = verticalSpacing ?? 8
    let contentWidth = columnWidths.reduce(0, +) + CGFloat(max(0, columns - 1)) * hGap
    let contentX = bounds.origin.x + _crossOffset(container: bounds.size.width, child: contentWidth, alignment: alignment.horizontalValue)
    var columnOffsets = Array(repeating: CGFloat.zero, count: columns)
    if columns > 1 {
      for column in 1..<columns {
        columnOffsets[column] = columnOffsets[column - 1] + columnWidths[column - 1] + hGap
      }
    }
    var rowOffsets = Array(repeating: CGFloat.zero, count: rowCount)
    if rowCount > 1 {
      for row in 1..<rowCount {
        rowOffsets[row] = rowOffsets[row - 1] + rowHeights[row - 1] + vGap
      }
    }
    for index in subviews.indices {
      let row = index / columns
      let column = index % columns
      let cellX: CGFloat = contentX + columnOffsets[column]
      let cellY: CGFloat = bounds.origin.y + rowOffsets[row]
      let x: CGFloat = cellX + _crossOffset(container: columnWidths[column], child: sizes[index].width, alignment: alignment.horizontalValue)
      let y: CGFloat = cellY + _crossOffset(container: rowHeights[row], child: sizes[index].height, alignment: alignment.verticalValue)
      subviews[index].place(
        at: CGPoint(x: x, y: y),
        proposal: ProposedViewSize(width: sizes[index].width, height: sizes[index].height)
      )
    }
  }
}

// MARK: - Layout rendering

/// Retained per-layout storage: the proposal the host last reported for a
/// user-defined `Layout`, and the one it was last evaluated with. Mutating it
/// never invalidates the view.
final package class _LayoutProposalStore {
  package init() {}
  package var reported = ProposedViewSize.unspecified
  package var rendered = ProposedViewSize.unspecified
  /// The sizes the host measured each subview at, with the proposal each was measured for (by subview index).
  package var measured: [Int: [(proposal: ProposedViewSize, size: CGSize)]] = .init()
  package var renderedMeasured: [Int: [(proposal: ProposedViewSize, size: CGSize)]] = .init()
}

#if hasFeature(Embedded)
@MainActor package func _semanticLayoutWrapper(_ semantic: _NodeValues, children: [_RenderNode]) -> _RenderNode {
  let wrapper = _RenderNode.element("div")
  wrapper.attributes = semantic
  wrapper.attributes["data-layout-schema"] = "1"
  wrapper.classes = ["layout-box"]
  wrapper.children = children
  return wrapper
}

@MainActor package func _hostLayoutProposal(_ proposal: ProposedViewSize, store: _LayoutProposalStore) -> ProposedViewSize {
  var proposal = proposal
  if let width = store.reported.width { proposal.width = width }
  if let height = store.reported.height { proposal.height = height }
  store.rendered = store.reported
  return proposal
}
#endif

@MainActor package func _layoutIdentifier<L: Layout>(_ layout: L) -> String {
  if let erased = layout as? AnyLayout {
    return "AnyLayout:\(erased._identifier)"
  }
  #if hasFeature(Embedded)
  return "layout:\(_swiftUIWebTypeName(L.self))"
  #else
  return _swiftUIWebTypeName(L.self)
  #endif
}

private func _gridRowChildren(_ node: _RenderNode) -> [_RenderNode] {
  node.children.flatMap { child in
    child.kind == .fragment ? child.children.flatMap(_flattenLayoutChildren) : [child]
  }
}

/// The columns a cell covers (`gridCellColumns(_:)`); a cell without the modifier covers one.
package func _gridCellColumnSpan(_ cell: _RenderNode) -> Int {
  guard let raw = cell.attributes["data-grid-cell-columns"], let parsed = Int(raw), parsed > 1 else { return 1 }
  let count = min(parsed, 1_000)
  return count
}

/// The axes a cell leaves out of grid sizing (`gridCellUnsizedAxes(_:)`). An unsized axis takes the column or row
/// size instead of contributing to it.
package func _gridCellUnsizedAxes(_ cell: _RenderNode) -> Axis.Set {
  guard let raw = cell.attributes["data-grid-unsized-axes"], let bits = Int8(raw) else { return [] }
  return Axis.Set(rawValue: bits)
}

/// The anchor a cell is placed by inside its grid slot (`gridCellAnchor(_:)`), if it has one.
package func _gridCellAnchor(_ cell: _RenderNode) -> UnitPoint? {
  guard let raw = cell.attributes["data-grid-cell-anchor"] else { return nil }
  let parts = raw.split(separator: ",").compactMap { Double($0) }
  guard parts.count == 2 else { return nil }
  return UnitPoint(x: parts[0], y: parts[1])
}

/// Column widths across all rows. The cells of one column size it first; then a cell spanning several columns widens
/// them evenly when they are still too narrow for it, so the spanned slot holds the cell. Sizing in that order makes the
/// widths independent of the order of the rows.
package func _gridColumnWidths(_ rows: [_RenderNode], _ horizontalSpacing: CGFloat) -> [Double] {
  var widths: [Double] = []
  var spanning: [(column: Int, span: Int, width: Double)] = []
  let gap = Double(horizontalSpacing)
  for row in rows {
    var column = 0
    for cell in _gridRowChildren(row) {
      let span = _gridCellColumnSpan(cell)
      let measured = _gridCellUnsizedAxes(cell).contains(.horizontal)
        ? 0 : Double(_LayoutNodeMeasurer.measure(cell, proposal: .unspecified).width)
      while widths.count < column + span { widths.append(0) }
      if span == 1 {
        widths[column] = max(widths[column], measured)
      } else {
        spanning.append((column, span, measured))
      }
      column += span
    }
  }
  for cell in spanning {
    let columns = cell.column..<(cell.column + cell.span)
    let covered = widths[columns].reduce(0, +) + Double(cell.span - 1) * gap
    if cell.width > covered {
      let extra = (cell.width - covered) / Double(cell.span)
      for spanned in columns { widths[spanned] += extra }
    }
  }
  return widths
}

/// The alignment each column takes from `gridColumnAlignment(_:)`, from the first cell in the column that sets one.
package func _gridColumnAlignments(_ rows: [_RenderNode]) -> [String?] {
  var alignments: [String?] = []
  for row in rows {
    var column = 0
    for cell in _gridRowChildren(row) {
      let span = _gridCellColumnSpan(cell)
      while alignments.count < column + span { alignments.append(nil) }
      if alignments[column] == nil, let value = cell.attributes["data-grid-column-alignment"] { alignments[column] = value }
      column += span
    }
  }
  return alignments
}

private func _gridRowContentSize(_ node: _RenderNode, _ horizontalSpacing: CGFloat, columnWidths: [Double]) -> CGSize {
  let cells = _gridRowChildren(node)
  let heights = cells.filter { !_gridCellUnsizedAxes($0).contains(.vertical) }
    .map { _LayoutNodeMeasurer.measure($0, proposal: .unspecified).height }
  let width = columnWidths.reduce(0, +) + Double(max(0, columnWidths.count - 1)) * Double(horizontalSpacing)
  return CGSize(width: width, height: heights.max() ?? 0)
}

/// Grid rows are ordinary SwiftUI layout children, not a browser CSS grid
/// dependency. Flattening their content here lets the same measurement and
/// placement algorithm assign every cell a concrete slot. Text cells receive
/// a span wrapper only in the renderer clone, preserving the source Fiber
/// identity while giving the DOM a stylable element.
package func _positionGridRowChildren(
  in row: _RenderNode,
  rowSize: CGSize,
  alignment: Alignment,
  horizontalSpacing: CGFloat,
  columnWidths: [Double]? = nil,
  columnAlignments: [String?] = []
) {
  let cells = _gridRowChildren(row)
  guard !cells.isEmpty else { return }
  let sizes = cells.map { _LayoutNodeMeasurer.measure($0, proposal: .unspecified) }
  let widths = columnWidths ?? sizes.map { Double($0.width) }
  let gap = Double(horizontalSpacing)
  var x: Double = 0
  var column = 0
  row.styles["position"] = "relative"
  row.styles["display"] = "block"
  row.children = cells.enumerated().map { index, original in
    let cell = original.clone()
    let measured = sizes[index]
    let span = _gridCellColumnSpan(original)
    let unsized = _gridCellUnsizedAxes(original)
    let anchor = _gridCellAnchor(original)
    // The slot is the covered columns and the gaps between them; a cell
    // that does not fit its slot keeps its measured size.
    let slotWidth: Double = column + span <= widths.count
      ? widths[column..<(column + span)].reduce(0, +) + Double(span - 1) * gap
      : Double(measured.width)
    let width = unsized.contains(.horizontal) ? slotWidth : Double(measured.width)
    let height = unsized.contains(.vertical) ? Double(rowSize.height) : Double(measured.height)
    let y: Double
    if let anchor {
      y = Double(rowSize.height - CGFloat(height)) * anchor.y
    } else {
      y = Double(_crossOffset(container: rowSize.height, child: CGFloat(height), alignment: alignment.verticalValue))
    }
    let horizontalAlignment: String = column < columnAlignments.count ? (columnAlignments[column] ?? alignment.horizontalValue) : alignment.horizontalValue
    // The offset places the resolved width, as `y` places the resolved height: a cell widened to its slot starts at it.
    let slotOffset: Double = anchor.map { (slotWidth - width) * $0.x }
      ?? Double(_crossOffset(container: CGFloat(slotWidth), child: CGFloat(width), alignment: horizontalAlignment))
    let output: _RenderNode
    if cell.kind == .text {
      let span = _RenderNode.element("span")
      span.key = cell.key
      span.attributes = cell.attributes
      span.styles = cell.styles
      span.classes = cell.classes
      span.children = [cell]
      output = span
    } else {
      output = cell
    }
    output.styles["position"] = "absolute"
    output.styles["box-sizing"] = "border-box"
    output.styles["left"] = "\(_layoutNumber(CGFloat(x + slotOffset)))px"
    output.styles["top"] = "\(_layoutNumber(CGFloat(y)))px"
    output.styles["width"] = "\(_layoutNumber(CGFloat(width)))px"
    output.styles["height"] = "\(_layoutNumber(CGFloat(height)))px"
    x += slotWidth + (column + span < widths.count ? gap : 0)
    column += span
    return output
  }
}

// MARK: - Internal measurement helpers

package func _flattenLayoutChildren(_ node: _RenderNode) -> [_RenderNode] {
  switch node.kind {
  case .empty: return []
  case .fragment: return node.children.flatMap(_flattenLayoutChildren)
  default: return [node]
  }
}

package enum _LayoutNodeMeasurer {
  static func spacing(for original: _RenderNode) -> ViewSpacing {
    let node = _SemanticLayers.unfolded(original)
    if node.classes.contains("flex-spacer") { return .zero }
    if let raw = node.attributes["data-layout-spacing"] {
      let values = raw.split(separator: ",").compactMap { CGFloat(Double($0) ?? 0) }
      if values.count == 4 { return ViewSpacing(top: values[0], leading: values[1], bottom: values[2], trailing: values[3]) }
    }
    let all = _number(node.styles["padding"]) ?? 0
    let top = _number(node.styles["padding-top"]) ?? _number(node.attributes["data-padding-top"]) ?? all
    let leading = _number(node.styles["padding-leading"]) ?? _number(node.styles["padding-left"])
      ?? _number(node.styles["padding-inline-start"])
      ?? _number(node.attributes["data-padding-leading"]) ?? all
    let bottom = _number(node.styles["padding-bottom"]) ?? _number(node.attributes["data-padding-bottom"]) ?? all
    let trailing = _number(node.styles["padding-trailing"]) ?? _number(node.styles["padding-right"])
      ?? _number(node.styles["padding-inline-end"])
      ?? _number(node.attributes["data-padding-trailing"]) ?? all
    return ViewSpacing(top: 4 + top, leading: 4 + leading, bottom: 4 + bottom, trailing: 4 + trailing)
  }

  package static func measure(_ original: _RenderNode, proposal: ProposedViewSize, resolveLayoutBoundary: Bool = true) -> CGSize {
    // One element can stand for a chain of layout wrappers (`_SemanticLayers`): measure the chain.
    let node = _SemanticLayers.unfolded(original)
    // A nested custom layout is a semantic measurement boundary. Resolve its
    // proposal hook once, then measure the returned snapshot without invoking
    // that hook again (the snapshot itself carries the same hook for future
    // parent proposals).
    if resolveLayoutBoundary, let render = node._layoutRender {
      let rendered = render(proposal)
      return measure(rendered, proposal: proposal, resolveLayoutBoundary: false)
    }
    var width = _dimension(node, key: "width", proposal: proposal.width)
    var height = _dimension(node, key: "height", proposal: proposal.height)
    let fixedWidth = node.styles["width"].map { _trimLayoutString($0) == "max-content" } ?? false
    let fixedHeight = node.styles["height"].map { _trimLayoutString($0) == "max-content" } ?? false
    let minContentWidth = node.styles["min-width"].map { _trimLayoutString($0) == "max-content" } ?? false
    let minContentHeight = node.styles["min-height"].map { _trimLayoutString($0) == "max-content" } ?? false
    let hasExplicitWidth = width != nil
    let hasExplicitHeight = height != nil
    if node.kind == .text {
      let text = node.text ?? ""
      let fontSize = _number(node.styles["font-size"]) ?? 16
      let lines = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
      // Custom Swift `Layout` executes synchronously before the browser can
      // answer an intrinsic-measurement wave. Use a deterministic system-text
      // approximation. Embedded uses the browser's `system-ui` metrics while
      // native rendering retains its established fallback; built-in layouts
      // replace this with real shaping in the browser.
      #if hasFeature(Embedded)
      let glyphScale = 0.494
      let lineScale = 1.18
      #else
      let glyphScale = 0.52
      let lineScale = 1.25
      #endif
      let intrinsicWidth = max(1, CGFloat(text.count)) * fontSize * glyphScale
      width = width ?? (fixedWidth || minContentWidth ? intrinsicWidth : min(proposal.width ?? .infinity, intrinsicWidth))
      height = height ?? CGFloat(lines) * fontSize * lineScale
    }
    if node.classes.contains("flex-spacer") {
      let minLength = _number(node.styles["--spacer-min-length"]) ?? 0
      width = width ?? minLength; height = height ?? minLength
    }
    if node.classes.contains("symbol-icon") {
      width = width ?? 16; height = height ?? 16
    } else if node.classes.contains("picture-view") {
      // Remote image dimensions are host-dependent. Keep a stable intrinsic
      // placeholder until the browser has a decoded asset to measure.
      width = width ?? 32; height = height ?? 32
    }
    if width == nil || height == nil {
      let measurementChildren: [_RenderNode]
      if node.classes.contains("hstack") || node.classes.contains("vstack") {
        // TupleView/Group content is represented as a fragment. Stack
        // measurement must see its individual arranged children rather than
        // treating that fragment as one max-sized container.
        measurementChildren = node.children.flatMap(_flattenLayoutChildren)
      } else {
        measurementChildren = node.children.filter { !$0.isEmpty }
      }
      let childSizes = measurementChildren.map { measure($0, proposal: proposal) }
      if node.classes.contains("hstack") {
        width = width ?? childSizes.reduce(0) { $0 + $1.width }
        height = height ?? childSizes.map { $0.height }.max() ?? 0
      } else if node.classes.contains("vstack") {
        width = width ?? childSizes.map { $0.width }.max() ?? 0
        height = height ?? childSizes.reduce(0) { $0 + $1.height }
      } else if node.classes.contains("grid-row") {
        // A GridRow's content is commonly a fragment nested one level below
        // the row node. Measure its cells as a horizontal sequence instead
        // of treating that fragment as one max-sized child.
        let cells = _gridRowChildren(node)
        let cellSizes = cells.map { measure($0, proposal: proposal) }
        width = width ?? cellSizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, cellSizes.count - 1)) * 8
        height = height ?? cellSizes.map { $0.height }.max() ?? 0
      } else {
        width = width ?? childSizes.map { $0.width }.max() ?? 0
        height = height ?? childSizes.map { $0.height }.max() ?? 0
      }
    }
    if !hasExplicitWidth { width = (width ?? 0) + _horizontalInset(of: node) }
    if !hasExplicitHeight { height = (height ?? 0) + _verticalInset(of: node) }
    if let proposalWidth = proposal.width, proposalWidth.isFinite, !fixedWidth, !minContentWidth {
      width = min(width ?? proposalWidth, proposalWidth)
      if let minimum = _number(node.styles["min-width"]) { width = max(width ?? minimum, minimum) }
    }
    if let proposalHeight = proposal.height, proposalHeight.isFinite, !fixedHeight, !minContentHeight {
      height = min(height ?? proposalHeight, proposalHeight)
      if let minimum = _number(node.styles["min-height"]) { height = max(height ?? minimum, minimum) }
    }
    return CGSize(width: max(0, width ?? 0), height: max(0, height ?? 0))
  }

  private static func _dimension(_ node: _RenderNode, key: String, proposal: CGFloat?) -> CGFloat? {
    var value = _number(node.styles[key]) ?? _number(node.attributes[key])
    if value == nil, let raw = node.styles[key], _trimLayoutString(raw) == "100%" { value = proposal }
    if key == "width" {
      if let minimum = _number(node.styles["min-width"]) { value = max(value ?? minimum, minimum) }
      if let maximum = _number(node.styles["max-width"]), let current = value { value = min(current, maximum) }
    } else if key == "height" {
      if let minimum = _number(node.styles["min-height"]) { value = max(value ?? minimum, minimum) }
      if let maximum = _number(node.styles["max-height"]), let current = value { value = min(current, maximum) }
    }
    return value
  }

  private static func _horizontalInset(of node: _RenderNode) -> CGFloat {
    let all = _number(node.styles["padding"]) ?? 0
    return (_number(node.styles["padding-leading"]) ?? _number(node.styles["padding-left"])
      ?? _number(node.styles["padding-inline-start"])
      ?? _number(node.attributes["data-padding-leading"]) ?? all) +
      (_number(node.styles["padding-trailing"]) ?? _number(node.styles["padding-right"])
        ?? _number(node.styles["padding-inline-end"])
        ?? _number(node.attributes["data-padding-trailing"]) ?? all)
  }

  private static func _verticalInset(of node: _RenderNode) -> CGFloat {
    let all = _number(node.styles["padding"]) ?? 0
    return (_number(node.styles["padding-top"]) ?? _number(node.attributes["data-padding-top"]) ?? all) +
      (_number(node.styles["padding-bottom"]) ?? _number(node.attributes["data-padding-bottom"]) ?? all)
  }
}

private func _number(_ value: String?) -> CGFloat? {
  guard let value else { return nil }
  let trimmed = _trimLayoutString(value)
  let numeric = trimmed.hasSuffix("px") ? String(trimmed.dropLast(2)) : trimmed
  guard let parsed = Double(numeric), parsed.isFinite else { return nil }
  return CGFloat(parsed)
}

// This parser intentionally uses the standard library so the layout core stays
// equally small on native and Embedded targets; it does not
// duplicate Foundation's CharacterSet API.
private func _trimLayoutString(_ value: String) -> String {
  String(value.filter { !$0.isWhitespace })
}

package func _layoutNumber(_ value: CGFloat) -> String {
  // A size beyond any screen is an "unbounded" proposal that leaked through (`greatestFiniteMagnitude`), like
  // infinity. `Int` is 32 bits in the browser build, so whole values go through `Int64`.
  guard value.isFinite, abs(value) < 1e12 else { return "0" }
  if value.rounded() == value { return String(Int64(value)) }
  return _swiftUIWebDescribe(Double(value))
}

private func _stackGaps(_ subviews: LayoutSubviews, axis: Axis, explicit: CGFloat?) -> [CGFloat] {
  guard subviews.count > 1 else { return [] }
  if let explicit { return Array(repeating: max(0, explicit), count: subviews.count - 1) }
  return (0..<(subviews.count - 1)).map { subviews[$0].spacing.distance(to: subviews[$0 + 1].spacing, along: axis) }
}

private func _crossOffset(container: CGFloat, child: CGFloat, alignment: VerticalAlignment) -> CGFloat {
  _crossOffset(container: container, child: child, alignment: alignment == .top ? "flex-start" : alignment == .bottom ? "flex-end" : "center")
}

private func _crossOffset(container: CGFloat, child: CGFloat, alignment: HorizontalAlignment) -> CGFloat {
  _crossOffset(container: container, child: child, alignment: alignment == .leading ? "flex-start" : alignment == .trailing ? "flex-end" : "center")
}

private func _crossOffset(container: CGFloat, child: CGFloat, alignment: String) -> CGFloat {
  switch alignment {
  case "flex-start", "start": return 0
  case "flex-end", "end": return max(0, container - child)
  default: return max(0, (container - child) / 2)
  }
}
