/// Internal leaf operation emitted by framework-owned controls. It is kept in
/// Core as renderer metadata so browser optimization never leaks DOM or
/// JavaScript concepts into the public SwiftUI-shaped API.
@_spi(Renderer) import SwiftUIWebTransferable
@_spi(Renderer) public enum _LeafBindingOperation: Hashable, Sendable {
  case textContent
  case property(String)
  case attribute(String)
  case style(String)
}

/// A proven value-to-target relationship. The getter is intentionally erased
/// at this boundary: Core does not know how a browser realizes the value, and
/// Fiber can retain one compact cell per descriptor. Unsupported/ambiguous
/// dependencies simply do not emit a descriptor and remain structural.
@_spi(Renderer) public struct _LeafBindingDescriptor {
  public let sourceID: _StateSourceID
  public let operation: _LeafBindingOperation
  public let value: () -> String

  public init(sourceID: _StateSourceID, operation: _LeafBindingOperation, value: @escaping () -> String) {
    self.sourceID = sourceID
    self.operation = operation
    self.value = value
  }
}

/// Axis used by a browser-backed lazy collection.  This metadata is emitted
/// by the normal SwiftUI-shaped `Lazy*` containers, but is consumed only by
/// the browser renderer.  Static/WASI hosts intentionally ignore it and keep
/// their deterministic eager tree.
@_spi(Renderer) public enum _LazyAxis: String, Hashable, Sendable {
  case vertical
  case horizontal
}

/// A deferred `ForEach` description.  The collection's closure is retained in
/// the structural graph rather than evaluating every row up front.  It is an
/// internal renderer descriptor: application code still writes ordinary
/// `ForEach` and never sees this type.
// Render descriptors are UI-thread-owned. A copied descriptor keeps its
// revision; reevaluating ForEach creates a new one even when IDs/count agree.
private let _nextLazyCollectionRevision = _Locked<UInt64>(1)

@_spi(Renderer) public struct _LazyCollectionDescriptor {
  public let revision: UInt64
  public let count: Int
  public let axis: _LazyAxis
  public let estimatedExtent: Double
  public let laneCount: Int
  public let itemType: String
  /// Semantic spacer tag used by hosts that require valid child elements
  /// (for example `<tr><td>` spacers inside a table body).  Ordinary lazy
  /// stacks keep the lightweight `div` default.
  public let spacerTag: String
  public let spacerColumnCount: Int
  public let keyAt: (Int) -> _FiberKey
  /// Checks whether an off-screen keyed row still belongs to the logical data
  /// source. Hosts use this to retain virtualized state without keeping state
  /// for rows that were actually removed from the collection.
  public let containsKey: (_FiberKey) -> Bool
  public let renderItem: (Int, _RenderContext) -> _RenderNode

  public init(
    count: Int,
    axis: _LazyAxis,
    estimatedExtent: Double = 64,
    laneCount: Int = 1,
    itemType: String = "",
    spacerTag: String = "div",
    spacerColumnCount: Int = 1,
    keyAt: @escaping (Int) -> _FiberKey,
    containsKey: @escaping (_FiberKey) -> Bool = { _ in false },
    renderItem: @escaping (Int, _RenderContext) -> _RenderNode
  ) {
    self.revision = _nextLazyCollectionRevision.withLock { next in
      precondition(next < UInt64.max, "Lazy collection revision space exhausted")
      defer { next += 1 }
      return next
    }
    self.count = max(0, count)
    self.axis = axis
    self.estimatedExtent = max(1, estimatedExtent)
    self.laneCount = max(1, laneCount)
    self.itemType = itemType
    self.spacerTag = spacerTag
    self.spacerColumnCount = max(1, spacerColumnCount)
    self.keyAt = keyAt
    self.containsKey = containsKey
    self.renderItem = renderItem
  }
}

/// Children of freed nodes, waiting to be freed by a loop (see `_RenderNode.deinit`).
final class _NodeGraveyard: @unchecked Sendable {
  private var draining = false
  private var pending: [[_RenderNode]] = []

  /// Takes `nodes` out of its owner and frees them from the outermost call, one batch at a time.
  func bury(_ nodes: inout [_RenderNode]) {
    pending.append(nodes)
    nodes = []
    if !draining { drain() }
  }

  /// Not optimized on purpose: releasing a batch is a call the optimizer takes to touch only the batch, so it
  /// would move it above the flag the nested releases read, and every level would start a loop of its own.
  @_optimize(none)
  private func drain() {
    draining = true
    while !pending.isEmpty {
      _ = pending.removeLast() // the batch is released here, while `draining` is set
    }
    draining = false
  }
}

/// Closures of freed objects, waiting to be freed by a loop. A navigation stack inside a navigation stack keeps its
/// parent alive through the action that dismisses it, so freeing the innermost frees the whole chain from inside each
/// `deinit`, a few frames per level of nesting; the chain is freed from the outermost call instead.
package final class _ClosureGraveyard: @unchecked Sendable {
  private var draining = false
  private var pending: [() -> Void] = []
  package init() {}

  /// Takes `action` out of its owner and frees it from the outermost call.
  package func bury(_ action: inout () -> Void) {
    pending.append(action)
    action = {}
    if !draining { drain() }
  }

  @_optimize(none)
  private func drain() {
    draining = true
    while !pending.isEmpty {
      var action = pending.removeLast()
      action = {}
      _ = action
    }
    draining = false
  }
}

public final class _RenderNode {
  /// A lifecycle-owned async operation. Tasks are kept separate from DOM
  /// events so multiple `.task` modifiers on one view compose instead of
  /// overwriting one another (for example, an initial feed load plus a
  /// comment submission task).
  public struct TaskRegistration {
    public let key: String
    public let id: String?
    public let start: () -> Void
    public let cancel: () -> Void

    public init(key: String, id: String?, start: @escaping () -> Void, cancel: @escaping () -> Void) {
      self.key = key
      self.id = id
      self.start = start
      self.cancel = cancel
      _RuntimeMemoryMetrics.recordTaskRegistration()
    }
  }

  public enum Kind: Equatable {
    case empty, fragment, text, element(String)
    public var displayName: String {
      switch self {
      case .empty: return "empty"
      case .fragment: return "fragment"
      case .text: return "text"
      case .element(let tag): return tag
      }
    }
  }
  // The reads below are inlined into every renderer. The writes are not: a write resolves the node and, on a node a
  // Fiber holds, compares what it had with what it gets (`sealedWrites`), and the framework sets a class, an attribute,
  // a style or the children in about two thousand places. Each write is one call (`_set…`), and an in-place edit
  // (`attributes[key] = value`, `children.append(_:)`) a call before it (`_open…`, which returns what a sealed node
  // held) and, for a sealed node only, one after it (`_close…`).
  public var kind: Kind {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sKind }
    @inline(__always) _modify {
      if _selfPending != nil { _resolveSelf() }
      if _sealed { let before = _sKind; yield &_sKind; if _sKind != before { Self.sealedWrites &+= 1 } } else { yield &_sKind }
    }
    @inline(__always) set { _setKind(newValue) }
  }
  var _sKind: Kind
  @inline(never) private func _setKind(_ newValue: __owned Kind) {
    if _selfPending != nil { _resolveSelf() }
    if _sealed && newValue != _sKind { Self.sealedWrites &+= 1 }
    _sKind = newValue
  }
  public var text: String? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sText }
    @inline(__always) _modify {
      if _selfPending != nil { _resolveSelf() }
      if _sealed { let before = _sText; yield &_sText; if _sText != before { Self.sealedWrites &+= 1 } } else { yield &_sText }
    }
    @inline(__always) set { _setText(newValue) }
  }
  var _sText: String?
  @inline(never) private func _setText(_ newValue: __owned String?) {
    if _selfPending != nil { _resolveSelf() }
    if _sealed && newValue != _sText { Self.sealedWrites &+= 1 }
    _sText = newValue
  }
  public var attributes: _NodeValues {
    @inline(__always) get { if _selfPending != nil || _awaitsChildren { _resolveAttributes() }; return _sAttributes }
    // An in-place edit (`attributes[key] = value`) does not need what the children decide; the mark they add is
    // merged into whatever the dictionary holds by then.
    @inline(__always) _modify {
      let before = _openAttributes()
      yield &_sAttributes
      if let before { _closeAttributes(before) }
    }
    @inline(__always) set { _setAttributes(newValue) }
  }
  var _sAttributes: _NodeValues
  @inline(never) private func _openAttributes() -> _NodeValues? {
    if _selfPending != nil { _resolveSelf() }
    return _sealed ? _sAttributes : nil
  }
  @inline(never) private func _closeAttributes(_ before: __owned _NodeValues) {
    if _sAttributes != before { Self.sealedWrites &+= 1 }
  }
  @inline(never) private func _setAttributes(_ newValue: __owned _NodeValues) {
    if _selfPending != nil || _awaitsChildren { _resolveAttributes() }
    if _sealed && newValue != _sAttributes { Self.sealedWrites &+= 1 }
    _sAttributes = newValue
  }
  public var styles: _NodeValues {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sStyles }
    @inline(__always) _modify {
      let before = _openStyles()
      yield &_sStyles
      if let before { _closeStyles(before) }
    }
    @inline(__always) set { _setStyles(newValue) }
  }
  var _sStyles: _NodeValues
  @inline(never) private func _openStyles() -> _NodeValues? {
    if _selfPending != nil { _resolveSelf() }
    return _sealed ? _sStyles : nil
  }
  @inline(never) private func _closeStyles(_ before: __owned _NodeValues) {
    if _sStyles != before { Self.sealedWrites &+= 1 }
  }
  @inline(never) private func _setStyles(_ newValue: __owned _NodeValues) {
    if _selfPending != nil { _resolveSelf() }
    if _sealed && newValue != _sStyles { Self.sealedWrites &+= 1 }
    _sStyles = newValue
  }
  public var classes: [String] {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sClasses }
    @inline(__always) _modify {
      let before = _openClasses()
      yield &_sClasses
      if let before { _closeClasses(before) }
    }
    @inline(__always) set { _setClasses(newValue) }
  }
  var _sClasses: [String]
  @inline(never) private func _openClasses() -> [String]? {
    if _selfPending != nil { _resolveSelf() }
    return _sealed ? _sClasses : nil
  }
  @inline(never) private func _closeClasses(_ before: __owned [String]) {
    if _sClasses != before { Self.sealedWrites &+= 1 }
  }
  @inline(never) private func _setClasses(_ newValue: __owned [String]) {
    if _selfPending != nil { _resolveSelf() }
    if _sealed && newValue != _sClasses { Self.sealedWrites &+= 1 }
    _sClasses = newValue
  }
  /// The nodes below this one. Reading them runs a deferred render of them, if there is one (`_RenderStaging`), so a
  /// reader always sees the rendered tree.
  public var children: [_RenderNode] {
    @inline(__always) get {
      if _selfPending != nil { _resolveSelf() }
      if _deferredChildren != nil { _materializeChildren() }
      return _children
    }
    @inline(__always) _modify {
      let before = _openChildren()
      yield &_children
      if let before { _closeChildren(before) }
    }
    @inline(__always) set { _setChildren(newValue) }
  }
  var _children: [_RenderNode]
  @inline(never) private func _openChildren() -> [_RenderNode]? {
    if _selfPending != nil { _resolveSelf() }
    if _deferredChildren != nil { _materializeChildren() }
    return _sealed ? _children : nil
  }
  @inline(never) private func _closeChildren(_ before: __owned [_RenderNode]) {
    if !_children.elementsEqual(before, by: ===) { Self.sealedWrites &+= 1 }
  }
  @inline(never) private func _setChildren(_ newValue: __owned [_RenderNode]) {
    if _selfPending != nil { _resolveSelf() }
    _deferredChildren = nil
    if _attributeJob != nil { _forgetAttributeJob() }
    if _sealed && !newValue.elementsEqual(_children, by: ===) { Self.sealedWrites &+= 1 }
    _children = newValue
  }
  /// Set once a Fiber holds this node (`_seal`). Writing a sealed node in place changes what a Fiber shows without a
  /// new node, so the reconcile must not take a node it gets again for unchanged (`_RenderNode.sealedWrites`).
  @_spi(Renderer) public private(set) var _sealed = false
  /// How many writes sealed nodes took. A pass notes it when it starts to render; a reconcile that sees a node it holds
  /// handed back unchanged skips the subtree only while no sealed node was written since.
  @_spi(Renderer) nonisolated(unsafe) public private(set) static var sealedWrites = 0
  @inline(__always) func _noteWrite() { if _sealed { Self.sealedWrites &+= 1 } }
  /// Marks the node as one a Fiber holds.
  @_spi(Renderer) public func _seal() { _sealed = true }
  /// The Fiber's own update of a child it holds (`propagateRenderedNodeToAncestors`): not a write of what it shows.
  @_spi(Renderer) public func _replaceRetainedChild(at index: Int, with child: _RenderNode) {
    if _deferredChildren != nil { _materializeChildren() }
    _children[index] = child
  }
  /// Set while this node stands in for a render that has not run yet; every read or write of the node runs it first.
  var _selfPending: _PendingRender?
  /// Set while the attributes of this node depend on children that have not been looked at yet (an `HStack` marks
  /// itself flexible when a `Spacer` is among them); reading or writing the attributes does that first.
  var _attributeJob: _OwnerCompletion?
  @inline(__always) var _awaitsChildren: Bool { _attributeJob != nil }
  /// Children that have not been rendered yet; `_children` is stale while this is set.
  var _deferredChildren: _DeferredChildren?
  /// Set on the node `_retainedRender(key:)` makes.
  @_spi(Renderer) public internal(set) var _retainsRenderedSubtree = false
  public var key: _FiberKey? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sKey }
    @inline(__always) _modify {
      if _selfPending != nil { _resolveSelf() }
      if _sealed { let before = _sKey; yield &_sKey; if _sKey != before { Self.sealedWrites &+= 1 } } else { yield &_sKey }
    }
    @inline(__always) set { _setKey(newValue) }
  }
  var _sKey: _FiberKey?
  @inline(never) private func _setKey(_ newValue: __owned _FiberKey?) {
    if _selfPending != nil { _resolveSelf() }
    if _sealed && newValue != _sKey { Self.sealedWrites &+= 1 }
    _sKey = newValue
  }
  public var descriptor: String? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sDescriptor }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sDescriptor }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sDescriptor = newValue }
  }
  var _sDescriptor: String?
  public var events: _NodeEvents {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sEvents }
    @inline(__always) _modify { _openEvents(); yield &_sEvents }
    @inline(__always) set { _openEvents(); _sEvents = newValue }
  }
  var _sEvents: _NodeEvents
  @inline(never) private func _openEvents() {
    if _selfPending != nil { _resolveSelf() }
    _noteWrite()
  }
  public var taskRegistrations: [TaskRegistration] {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sTaskRegistrations }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sTaskRegistrations }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sTaskRegistrations = newValue }
  }
  var _sTaskRegistrations: [TaskRegistration]
  /// Number of `onChange` modifiers applied to this node in the current
  /// render. Each modifier gets its own history slot, so several `onChange`
  /// modifiers on one view observe their values independently, as in SwiftUI.
  package var _onChangeCount: Int {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sOnChangeCount }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sOnChangeCount }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sOnChangeCount = newValue }
  }
  var _sOnChangeCount = 0
  /// Renderer-only descriptors for direct updates. They are deliberately not
  /// considered semantic equality: the surrounding Fiber remains authoritative
  /// and a descriptor change is synchronized by the binding runtime.
  @_spi(Renderer) public var leafBindings: [_LeafBindingDescriptor] {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sLeafBindings }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sLeafBindings }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sLeafBindings = newValue }
  }
  var _sLeafBindings: [_LeafBindingDescriptor]
  /// Sensitive form value resolver used only by the Embedded host to hydrate
  /// a SecureField's live DOM property. The returned string is never copied
  /// into serialized attributes, HTML, semantic equality or diagnostics.
  @_spi(Renderer) public var _secureValue: (() -> String)? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sSecureValue }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sSecureValue }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sSecureValue = newValue }
  }
  var _sSecureValue: (() -> String)?
  /// A deferred lazy collection emitted by `ForEach` when it is evaluated
  /// below a `LazyV*`/`LazyH*` container.  Kept separate from children so the
  /// browser can materialize only the visible logical range.
  @_spi(Renderer) public var lazyCollection: _LazyCollectionDescriptor? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sLazyCollection }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sLazyCollection }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sLazyCollection = newValue }
  }
  var _sLazyCollection: _LazyCollectionDescriptor?
  /// Erased-view owner used by the hierarchical invalidation scheduler.  It
  /// is renderer metadata only and never participates in semantic equality.
  @_spi(Renderer) public var _renderOwnerToken: UInt64? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sRenderOwnerToken }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sRenderOwnerToken }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sRenderOwnerToken = newValue }
  }
  var _sRenderOwnerToken: UInt64?
  /// Set by `onHover(_assigning:)`: the state that hover toggles, so the renderer can learn the hovered look ahead of time.
  @_spi(Renderer) public var _hoverProbe: _HoverProbe? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sHoverProbe }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sHoverProbe }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sHoverProbe = newValue }
  }
  var _sHoverProbe: _HoverProbe?
  /// Exact value-state scopes represented by this node. A conditional can
  /// render one branch into its parent's node, so its branch scope must remain
  /// explicit even when the outer erased owner token is the Fiber's primary
  /// invalidation target.
  @_spi(Renderer) public var _stateScopePaths: [_FiberPath] {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sStateScopePaths }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sStateScopePaths }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sStateScopePaths = newValue }
  }
  var _sStateScopePaths: [_FiberPath] { didSet { _sStateScopePathIndex = nil } }
  /// The same paths as a set, built by `_recordStateScopePath` once a node has many of them (a chain of modifiers
  /// renders into one node and records the path of each level), so that recording is not linear in what was recorded.
  /// Any other change to the list drops it.
  var _sStateScopePathIndex: Set<_FiberPath>?
  /// Canonical semantic description of a subtree that the renderer has
  /// proven safe to retain.  This is deliberately renderer metadata: it is
  /// computed from the complete _RenderNode shape and is never part of the
  /// SwiftUI-facing API.  Host annotations are excluded by the Fiber layer so
  /// adding DOM bookkeeping does not invalidate a static template.
  @_spi(Renderer) public var _staticTemplateKey: String? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sStaticTemplateKey }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sStaticTemplateKey }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sStaticTemplateKey = newValue }
  }
  var _sStaticTemplateKey: String?
  /// Type-erased values attached by `layoutValue(key:value:)`.  The storage
  /// is renderer metadata; custom layouts read it through `LayoutSubview` and
  /// the public API never needs to know how a host stores the value.
  @_spi(Renderer) public var _layoutValues: [ObjectIdentifier: AnyObject] {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sLayoutValues }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sLayoutValues }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sLayoutValues = newValue }
  }
  var _sLayoutValues: [ObjectIdentifier: AnyObject]
  /// Optional re-render hook used by nested custom layouts to honor a new
  /// proposal. It is renderer metadata and is ignored by ordinary views.
  @_spi(Renderer) public var _layoutRender: ((ProposedViewSize) -> _RenderNode)? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sLayoutRender }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sLayoutRender }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sLayoutRender = newValue }
  }
  var _sLayoutRender: ((ProposedViewSize) -> _RenderNode)?
  /// Alignment-guide computations attached by `.alignmentGuide(...)`.
  @_spi(Renderer) public var _layoutAlignmentGuides: [String: (ViewDimensions) -> CGFloat] {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sLayoutAlignmentGuides }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sLayoutAlignmentGuides }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sLayoutAlignmentGuides = newValue }
  }
  var _sLayoutAlignmentGuides: [String: (ViewDimensions) -> CGFloat]
  /// Explicit alignment supplied by a custom `Layout`. Unlike child
  /// alignment-guide closures, these resolvers accept any custom
  /// `AlignmentID` requested by an enclosing layout.
  @_spi(Renderer) public var _layoutExplicitHorizontalAlignment: ((HorizontalAlignment) -> CGFloat?)? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sLayoutExplicitHorizontalAlignment }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sLayoutExplicitHorizontalAlignment }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sLayoutExplicitHorizontalAlignment = newValue }
  }
  var _sLayoutExplicitHorizontalAlignment: ((HorizontalAlignment) -> CGFloat?)?
  @_spi(Renderer) public var _layoutExplicitVerticalAlignment: ((VerticalAlignment) -> CGFloat?)? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sLayoutExplicitVerticalAlignment }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sLayoutExplicitVerticalAlignment }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sLayoutExplicitVerticalAlignment = newValue }
  }
  var _sLayoutExplicitVerticalAlignment: ((VerticalAlignment) -> CGFloat?)?
  /// Type-erased table-cell renderer attached by `TableColumn`.  This keeps
  /// column closures available to a deferred table descriptor without
  /// exposing renderer storage (or requiring reflection) through the public
  /// SwiftUI-shaped API.
  // Retain a tag identity across render passes, including Embedded custom enums.
  var _tagIdentity: _FiberKey? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sTagIdentity }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sTagIdentity }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sTagIdentity = newValue }
  }
  var _sTagIdentity: _FiberKey?
  var _pickerSelectionValue: _RuntimeValue? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sPickerSelectionValue }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sPickerSelectionValue }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sPickerSelectionValue = newValue }
  }
  var _sPickerSelectionValue: _RuntimeValue?
  @_spi(Renderer) public var _tableCellRender: ((_RuntimeValue, _RenderContext) -> _RenderNode)? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sTableCellRender }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sTableCellRender }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sTableCellRender = newValue }
  }
  var _sTableCellRender: ((_RuntimeValue, _RenderContext) -> _RenderNode)?
  /// Typed sort descriptor (`_TableColumnSort<Row>`) attached by a sortable `TableColumn`.
  @_spi(Renderer) public var _tableColumnSort: _RuntimeValue? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sTableColumnSort }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sTableColumnSort }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sTableColumnSort = newValue }
  }
  var _sTableColumnSort: _RuntimeValue?
  /// Typed row value attached by `TableRow` so a rows-form `Table` can collect its data.
  @_spi(Renderer) public var _tableRowValue: _RuntimeValue? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sTableRowValue }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sTableRowValue }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sTableRowValue = newValue }
  }
  var _sTableRowValue: _RuntimeValue?
  /// Backend-neutral drawing commands emitted by `Canvas`.  The command IR is
  /// independent of DOM/JavaScript so other hosts can add a renderer without
  /// changing the Swift-facing API.
  @_spi(Renderer) public var _canvasCommands: [_CanvasCommand] {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sCanvasCommands }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sCanvasCommands }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sCanvasCommands = newValue }
  }
  var _sCanvasCommands: [_CanvasCommand]
  /// Stable digest used by browser hosts to skip an identical redraw while
  /// retaining the existing canvas element and 2D context.
  @_spi(Renderer) public var _canvasFingerprint: String? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sCanvasFingerprint }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sCanvasFingerprint }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sCanvasFingerprint = newValue }
  }
  var _sCanvasFingerprint: String?
  /// Browser-neutral drag source metadata.  Host adapters attach native
  /// listeners only for nodes carrying this descriptor.
  @_spi(Renderer) public var _dragSource: _DragSourceDescriptor? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sDragSource }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sDragSource }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sDragSource = newValue }
  }
  var _sDragSource: _DragSourceDescriptor?
  /// Browser-neutral drop target metadata.  The accepted UTI list is emitted
  /// as a compact attribute; the closure remains in the retained Fiber tree.
  @_spi(Renderer) public var _dropTarget: _DropTargetDescriptor? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sDropTarget }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sDropTarget }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sDropTarget = newValue }
  }
  var _sDropTarget: _DropTargetDescriptor?
  /// Renderer-neutral timeline scheduling metadata. Browser hosts use this to
  /// arm one private timer/animation-frame loop per mounted TimelineView;
  /// static/WASI renderers ignore it.
  @_spi(Renderer) public var _timeline: _TimelineDescriptor? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sTimeline }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sTimeline }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sTimeline = newValue }
  }
  var _sTimeline: _TimelineDescriptor?
  /// Lifecycle callbacks for a component mounted in the browser's current DOM.
  @_spi(Renderer) public var _domView: _DOMViewDescriptor? {
    @inline(__always) get { if _selfPending != nil { _resolveSelf() }; return _sDomView }
    @inline(__always) _modify { if _selfPending != nil { _resolveSelf() }; yield &_sDomView }
    @inline(__always) set { if _selfPending != nil { _resolveSelf() }; _sDomView = newValue }
  }
  var _sDomView: _DOMViewDescriptor?

  public init(kind: Kind, text: String? = nil) {
    self._sKind = kind; self._sText = text; _sAttributes = .init(); _sStyles = .init(); _sClasses = []
    _children = []; _deferredChildren = nil; _selfPending = nil; _sDescriptor = nil; _sEvents = .init(); _sTaskRegistrations = []; _sLeafBindings = []; _sSecureValue = nil; _sPickerSelectionValue = nil; _sLazyCollection = nil; _sRenderOwnerToken = nil; _sHoverProbe = nil; _sStateScopePaths = []; _sStaticTemplateKey = nil; _sLayoutValues = .init(); _sLayoutRender = nil; _sLayoutAlignmentGuides = .init(); _sLayoutExplicitHorizontalAlignment = nil; _sLayoutExplicitVerticalAlignment = nil; _sTableCellRender = nil; _sTableColumnSort = nil; _sTableRowValue = nil; _sCanvasCommands = []; _sCanvasFingerprint = nil; _sDragSource = nil; _sDropTarget = nil; _sTimeline = nil; _sDomView = nil
    _RuntimeMemoryMetrics.recordRenderNodeInit()
    if let text { _RuntimeMemoryMetrics.observeString(text) }
  }

  deinit {
    _RuntimeMemoryMetrics.recordRenderNodeDeinit()
    if !_children.isEmpty { _releaseChildren() }
  }

  /// Releases the children without recursing: freeing a tree is a recursion of its own (a node's deinit frees its
  /// children array, whose elements' deinits free theirs), about seven WebAssembly frames per level of the tree,
  /// and a tree built from a deep view hierarchy would use more stack to die than it took to render. Past a
  /// nesting limit the children wait in the thread's graveyard and the outermost release frees them in a loop.
  @inline(never)
  private func _releaseChildren() {
    _RenderThreadState.current.nodeGraveyard.bury(&_children)
  }
  public static func empty() -> _RenderNode { _RenderNode(kind: .empty) }
  public static func fragment() -> _RenderNode { _RenderNode(kind: .fragment) }
  public static func text(_ text: String) -> _RenderNode { _RenderNode(kind: .text, text: text) }
  public static func element(_ tag: String) -> _RenderNode { _RenderNode(kind: .element(tag)) }
  public var isEmpty: Bool { kind == .empty }

  /// Stands in for the subtree the Fiber already holds at this position (the child keyed `key`): the reconcile keeps
  /// that subtree, its state and owners as they are, without walking it, and puts its node where this one is. A view
  /// hands it back for content it does not need to build again, such as a hidden tab already built. With nothing to
  /// keep there, it is an empty `div`.
  @_spi(Renderer) public static func _retainedRender(key: _FiberKey?) -> _RenderNode {
    let node = _RenderNode(kind: .element("div"))
    node._sKey = key
    node._retainsRenderedSubtree = true
    return node
  }

  /// A copy of this node that adopts the same child nodes instead of cloning
  /// them. For modifiers that turn `self` into a wrapper around the copy: the
  /// children then belong to the copy alone, so a deep clone (quadratic in
  /// the nesting of layout modifiers) would only duplicate work.
  public func cloneSharingChildren() -> _RenderNode {
    let copy = clone(cloningChildren: false)
    // Share the children as they are: a deferred render stays deferred and both nodes read the same result.
    copy._children = _children
    copy._deferredChildren = _deferredChildren
    if let record = _attributeJob {
      // The attributes that wait for the children belong with them, on the copy: this node is about to turn into a
      // wrapper around it (see above), and the copy is the one that stands for the original.
      copy._attributeJob = record
      record.owner = copy
      _attributeJob = nil
    }
    return copy
  }

  public func clone() -> _RenderNode { clone(cloningChildren: true) }

  private func clone(cloningChildren: Bool) -> _RenderNode {
    if _selfPending != nil { _resolveSelf() }
    // The attributes below are read as they stand: the children that settle them have to have rendered.
    if cloningChildren {
      if _deferredChildren != nil { _materializeChildren() }
      if _attributeJob != nil { _resolveAttributes() }
    }
    let copy = _RenderNode(kind: kind, text: text)
    copy._sAttributes = _sAttributes; copy._sStyles = _sStyles; copy._sClasses = _sClasses; copy._sKey = _sKey; copy._sDescriptor = _sDescriptor; copy._sEvents = _sEvents; copy._sTaskRegistrations = _sTaskRegistrations; copy._sLeafBindings = _sLeafBindings; copy._sSecureValue = _sSecureValue; copy._sLazyCollection = _sLazyCollection; copy._sRenderOwnerToken = _sRenderOwnerToken; copy._sHoverProbe = _sHoverProbe; copy._sStateScopePaths = _sStateScopePaths; copy._sStateScopePathIndex = _sStateScopePathIndex; copy._sStaticTemplateKey = _sStaticTemplateKey; copy._sLayoutValues = _sLayoutValues; copy._sLayoutRender = _sLayoutRender; copy._sLayoutAlignmentGuides = _sLayoutAlignmentGuides; copy._sLayoutExplicitHorizontalAlignment = _sLayoutExplicitHorizontalAlignment; copy._sLayoutExplicitVerticalAlignment = _sLayoutExplicitVerticalAlignment; copy._sTagIdentity = _sTagIdentity; copy._sPickerSelectionValue = _sPickerSelectionValue; copy._sTableCellRender = _sTableCellRender; copy._sTableColumnSort = _sTableColumnSort; copy._sTableRowValue = _sTableRowValue; copy._sCanvasCommands = _sCanvasCommands; copy._sCanvasFingerprint = _sCanvasFingerprint; copy._sDragSource = _sDragSource; copy._sDropTarget = _sDropTarget; copy._sTimeline = _sTimeline; copy._sDomView = _sDomView
    if cloningChildren { copy.children = children.map { $0.clone() } }
    return copy
  }

  /// A copy to remember a view's render by (`_RenderOwnerRegistry._rememberView`) and to hand out again: this node's
  /// own state with the same children, as they are now. What wraps the view writes into the node it gets, and into the
  /// child of a keyless one-child fragment (`_modifierTarget`), so that child is copied the same way. Nil while the node
  /// still waits for its render or for its children to settle its attributes, which a copy would not see finish.
  func _reuseSnapshot() -> _RenderNode? {
    guard _selfPending == nil, _attributeJob == nil else { return nil }
    let copy = clone(cloningChildren: false)
    copy._children = _children
    copy._deferredChildren = _deferredChildren
    if kind == .fragment, key == nil {
      guard _deferredChildren == nil else { return nil }
      if _children.count == 1 {
        guard let child = _children[0]._reuseSnapshot() else { return nil }
        copy._children = [child]
      }
    }
    return copy
  }

  /// Takes `other`'s whole state, which is how a node that stood in for a render that had not run yet (see
  /// `_RenderStaging`) turns into what that render produced. `other` is not used afterwards.
  func _become(_ other: _RenderNode) {
    if other._selfPending != nil { other._resolveSelf() }
    _sKind = other._sKind; _sText = other._sText; _sAttributes = other._sAttributes; _sStyles = other._sStyles; _sClasses = other._sClasses; _sKey = other._sKey; _sDescriptor = other._sDescriptor; _sEvents = other._sEvents; _sTaskRegistrations = other._sTaskRegistrations; _sOnChangeCount = other._sOnChangeCount; _sLeafBindings = other._sLeafBindings; _sSecureValue = other._sSecureValue; _sLazyCollection = other._sLazyCollection; _sRenderOwnerToken = other._sRenderOwnerToken; _sHoverProbe = other._sHoverProbe; _sStateScopePaths = other._sStateScopePaths; _sStateScopePathIndex = other._sStateScopePathIndex; _sStaticTemplateKey = other._sStaticTemplateKey; _sLayoutValues = other._sLayoutValues; _sLayoutRender = other._sLayoutRender; _sLayoutAlignmentGuides = other._sLayoutAlignmentGuides; _sLayoutExplicitHorizontalAlignment = other._sLayoutExplicitHorizontalAlignment; _sLayoutExplicitVerticalAlignment = other._sLayoutExplicitVerticalAlignment; _sTagIdentity = other._sTagIdentity; _sPickerSelectionValue = other._sPickerSelectionValue; _sTableCellRender = other._sTableCellRender; _sTableColumnSort = other._sTableColumnSort; _sTableRowValue = other._sTableRowValue; _sCanvasCommands = other._sCanvasCommands; _sCanvasFingerprint = other._sCanvasFingerprint; _sDragSource = other._sDragSource; _sDropTarget = other._sDropTarget; _sTimeline = other._sTimeline; _sDomView = other._sDomView
    _children = other._children
    _deferredChildren = other._deferredChildren
    _attributeJob = other._attributeJob
    _attributeJob?.owner = self
    other._children = []
    other._deferredChildren = nil
    other._attributeJob = nil
    _selfPending = nil
  }

  public func shallowEquals(_ other: _RenderNode) -> Bool {
    guard kind == other.kind, text == other.text, attributes == other.attributes,
          styles == other.styles, classes == other.classes, key == other.key,
          descriptor == other.descriptor, events.hasSameNames(as: other.events),
          taskRegistrations.map({ $0.key + "|" + ($0.id ?? "<nil>") }) ==
          other.taskRegistrations.map({ $0.key + "|" + ($0.id ?? "<nil>") }) else { return false }
    return true
  }

  public func structuralEquals(_ other: _RenderNode) -> Bool {
    guard shallowEquals(other), children.count == other.children.count else { return false }
    return zip(children, other.children).allSatisfy { $0.structuralEquals($1) }
  }
}

public struct _EventHandler {
  public let name: String
  public let action: @MainActor () -> Void
  public let valueAction: (@MainActor (String) -> Void)?
  /// Whether a browser adapter should call `preventDefault()` before
  /// invoking this handler. Most SwiftUIWeb events are additive; navigation
  /// links and form submissions opt in because they own the transition.
  public let preventsDefault: Bool

  public init(name: String, action: @escaping @MainActor () -> Void, preventsDefault: Bool = false) {
    self.name = name
    self.action = _EventHandler.scoped(action)
    valueAction = nil
    self.preventsDefault = preventsDefault
    _RuntimeMemoryMetrics.recordEventHandler()
  }
  public init(name: String, action: @escaping @MainActor (String) -> Void, preventsDefault: Bool = false) {
    self.name = name
    self.action = {}
    let scoped = _EventHandler.scoped(action)
    valueAction = { value in scoped(value) }
    self.preventsDefault = preventsDefault
    _RuntimeMemoryMetrics.recordEventHandler()
  }

  /// Combined action/value handler used by gesture phases. Browser hosts send
  /// the compact value for continuous gestures, while static/WASI tests and
  /// simple hosts may dispatch the phase without a payload.
  public init(name: String, action: @escaping @MainActor () -> Void, valueAction: @escaping @MainActor (String) -> Void, preventsDefault: Bool = false) {
    self.name = name
    self.action = _EventHandler.scoped(action)
    let scoped = _EventHandler.scoped(valueAction)
    self.valueAction = { value in scoped(value) }
    self.preventsDefault = preventsDefault
    _RuntimeMemoryMetrics.recordEventHandler()
  }

  /// Handlers run with the environment of the render that created them.
  /// Synchronous reads see it directly, and `Task {}` bodies started by the
  /// handler inherit it as a task-local value, so an action that awaits
  /// before reading `@Environment` still sees its view's environment.
  private static func scoped(_ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
    let environment = EnvironmentRuntime.installed
    return { EnvironmentRuntime.perform(with: environment, action) }
  }

  private static func scoped(_ action: @escaping @MainActor (String) -> Void) -> @MainActor (String) -> Void {
    let environment = EnvironmentRuntime.installed
    return { value in EnvironmentRuntime.perform(with: environment) { action(value) } }
  }
}
