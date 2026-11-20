@_spi(Renderer) import SwiftUIWebTransferable
#if canImport(Observation) && !hasFeature(Embedded)
#endif

/// The owner token is assigned immediately after an erased view registers its
/// retained render closure. Observation callbacks are `@Sendable`, so the
/// token needs a tiny reference box instead of capturing a mutable local.
private final class _RenderOwnerTokenBox: @unchecked Sendable {
  var value: UInt64 = 0
}

/// The value-description protocol used by SwiftUIWeb applications.
@MainActor @preconcurrency
public protocol View {
  associatedtype Body: View
  @ViewBuilder
  @MainActor @preconcurrency var body: Body { get }
  func _render(in context: _RenderContext) -> _RenderNode
  /// Whether `_sameInputs` compares this view's inputs. The source lowering writes both for an application's views;
  /// without them a view's body runs whenever its parent's does.
  static var _comparesInputs: Bool { get }
  /// Whether two values of this view have the same inputs: what its parent gave it, not its state or environment
  /// (`ViewInputs.swift`). A view whose inputs, environment and state are unchanged is not rendered again.
  static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool
  /// Whether the view renders through its own `_render` although it has a body: an `Animatable` view renders its body
  /// with the data its animation has reached (`Animator.swift`), so a renderer must not form the body itself.
  static var _swiftUIWebRendersItself: Bool { get }
  /// Installs the view's `@State` and `@StateObject` properties in the current state scope, before its body is formed:
  /// SwiftUI installs a view's state before it evaluates the body, so the body, the closures it builds and the actions
  /// it registers (`onAppear`, a button's action) all read the storage of the view's identity, never the initial value
  /// a later value of the view brings. The source lowering writes it for an application's views (Embedded Swift has no
  /// reflection); elsewhere the default finds the properties with a `Mirror`.
  func _installState()
}

/// Collections below this size stay on the ordinary eager path when the
/// container has not explicitly requested lazy semantics (List/Table). The
/// threshold is renderer policy rather than a SwiftUI-facing knob; explicit
/// Lazy* containers force the descriptor path even for short collections.
package let _lazyCollectionThreshold = 16

public extension View {
  static var _comparesInputs: Bool { false }
  static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { false }
  static var _swiftUIWebRendersItself: Bool { false }
  package nonisolated func eraseToAnyView() -> AnyView { AnyView(self) }
  func _render(in context: _RenderContext) -> _RenderNode {
    _installState()
    return body._render(in: context)
  }
  func _installState() {
    #if !hasFeature(Embedded)
    _installStateByReflection(self)
    #endif
  }
}

public extension View where Body == Never {
  var body: Never { fatalError("Primitive views do not expose a body") }
}

/// The environment and state scope that `_enterRenderScope` replaced, for
/// `_exitRenderScope` to restore.
struct _RenderScopeSaved {
  fileprivate let environment: EnvironmentValues?
  fileprivate let scope: StateScope?
}

/// Debug-only record of how deeply erased view boundaries nest while rendering. Off unless a host turns it on
/// (`?stack-depth=1` in the browser runtime); when off, a boundary pays one load and one branch. The observer lets
/// the host sample the call-stack headroom left at that point, which is what bounds a view tree in a WebKit Worker.
@MainActor package enum _RenderDepthMeter {
  package static var enabled = false
  package private(set) static var depth = 0
  package private(set) static var maxDepth = 0
  package static var observer: ((Int) -> Void)?
  @inline(never) static func entered() {
    depth += 1
    if depth > maxDepth { maxDepth = depth }
    observer?(depth)
  }
  @inline(never) static func exited() { if depth > 0 { depth -= 1 } }
}

/// Installs `context`'s environment and a fresh state scope for `viewTag`,
/// returning what it replaced. Every erased view boundary needs exactly this
/// bookkeeping; keeping it in a non-generic function means an `AnyView<V>`
/// closure specializes only the call into `V._render`, not the scope
/// handling, for each of the application's view types.
///
/// Enter/exit pairs instead of a `withScope { ... }` closure because every
/// erased boundary sits on the render recursion: a closure argument costs the
/// scope function's frame plus the closure's specialization, reabstraction
/// and partial-apply frames, and WebKit runs a Worker's WebAssembly on a stack
/// small enough that those frames bound how deep a view tree renders.
@inline(never)
@MainActor func _enterRenderScope(_ context: _RenderContext, viewTag: String) -> _RenderScopeSaved {
  if _RenderDepthMeter.enabled { _RenderDepthMeter.entered() }
  _RenderStaging.state.depth &+= 1
  let saved = _RenderScopeSaved(environment: EnvironmentRuntime.installed, scope: StateRuntime.scope)
  EnvironmentRuntime.current = context.environment
  StateRuntime.scope = StateScope(context: context, viewTag: viewTag)
  return saved
}

/// Restores the environment and state scope `_enterRenderScope` replaced.
@inline(never)
@MainActor func _exitRenderScope(_ saved: _RenderScopeSaved) {
  if _RenderDepthMeter.enabled { _RenderDepthMeter.exited() }
  EnvironmentRuntime.installed = saved.environment
  StateRuntime.scope = saved.scope
  // The outermost level of a pass is over: render the children the pass deferred (see `_RenderStaging`).
  let staging = _RenderStaging.state
  staging.depth &-= 1
  if staging.depth <= 0, staging.hasPending || !staging.finalizers.isEmpty || !staging.orderedEffects.isEmpty || !staging.stages.isEmpty { _RenderStaging.drive() }
}

/// Forms a non-primitive view's body separately from rendering the body tree.
/// Swift Observation tracking scopes are compositional: if an erased parent
/// tracks all the way through nested `AnyView` children, the parent also
/// records every descendant model read. Forming the body while the parent
/// scope is active, then rendering the returned value after that scope ends,
/// preserves direct dependencies without widening them to descendants.
/// Primitive views (`Body == Never`) keep their custom renderer path.
@MainActor private func _makeObservationBodyRenderer<V: View>(_ view: V) -> @MainActor (_RenderContext) -> _RenderNode {
  if V.Body.self == Never.self || V._swiftUIWebRendersItself {
    let tag = _swiftUIWebTypeName(V.self)
    return { context in
      let saved = _enterRenderScope(context, viewTag: tag)
      let node = view._render(in: context)
      _exitRenderScope(saved)
      return node
    }
  }
  view._installState()
  // Form every body-backed layer while the current owner is tracked. The
  // final primitive/container renderer runs later, outside this access list;
  // nested AnyViews then install their own native tracking scopes.
  return _makeObservationBodyRenderer(view.body)
}

/// Wraps a renderer so the node it returns carries `tag` as its descriptor.
/// Non-generic so `AnyView<V>` does not specialize this closure per `V`.
@inline(never)
func _describedRenderer(_ render: @escaping @MainActor (_RenderContext) -> _RenderNode, tag: String) -> @MainActor (_RenderContext) -> _RenderNode {
  { context in
    let node = render(context)
    node._postDescriptor(tag)
    return node
  }
}

/// Renderer-owned records for an erased view boundary.  The normal SwiftUI
/// API never exposes these handles; they let the retained browser renderer
/// reevaluate one owner scope after a state write without asking the root view
/// to rebuild.  A registry is deliberately reference-backed so copied
/// `_RenderContext` values continue to share one contiguous ownership table.
@MainActor @_spi(Renderer) public final class _RenderOwnerRegistry {
  private struct Entry {
    var context: _RenderContext
    var render: (_RenderContext) -> _RenderNode
  }

  private var nextToken: UInt64 = 1
  private var entries: [UInt64: Entry] = .init()
  /// How many owners are registered: owners a mounted view no longer has must not stay (a test hook).
  @_spi(Renderer) public var _registeredOwnerCount: Int { entries.count + outerOwners.count + innerOwners.count + aliasableOwners.count }
  private let retiredPathLimit = 4096
  private var retiredPaths: [UInt64: _FiberPath] = .init()
  private var retiredPathTokens: [UInt64] = []
  private var retiredPathCursor = 0
  /// Owners whose node was returned unchanged by an enclosing owner. The
  /// retained node carries the enclosing token, so a reader recorded under the
  /// inner token routes to the enclosing owner's Fiber.
  private var outerOwners: [UInt64: UInt64] = .init()
  /// The other way round: the inner owner whose node an owner returned last (a node carries one owner, so an owner has
  /// one inner owner at a time). An inner owner carries no Fiber of its own, so nothing else retires it: when an owner
  /// renders again its previous inner owner is retired as the new one is recorded, and it goes when the owner goes.
  /// Without this, every render left the previous render's inner owners registered for good.
  private var innerOwners: [UInt64: UInt64] = .init()
  private var aliasableOwners: Set<UInt64> = []
  /// Owners being rendered again keep their tokens: a token waiting here is handed back to the owner registered
  /// at the same structural path (the k-th registration of a path takes its k-th token). A re-render then leaves
  /// every owner still mounted at its path with the token its Fiber already holds; a fresh token per pass made the
  /// Fiber re-index each of a list's rows on every pass. Both branches of a conditional register at one path: they
  /// are one owner, so the token stays with whichever branch is shown.
  private var reusableByPath: [_FiberPath: [UInt64]] = .init()
  private var reusedCount: [_FiberPath: Int] = .init()
  /// Tokens the current render handed back to an owner (by path or by `_claim`). The Fibers that held them
  /// before the render are released during reconciliation, after the new owner registered; their release must
  /// not remove the entry the new owner now holds.
  private var reclaimed: Set<UInt64> = []
  /// The tokens each open recording registered (`_beginRecordingRegistrations`), innermost last. A recording
  /// that is discarded retires what its render registered, so an owner the render made for a node nobody keeps
  /// does not stay registered.
  private var recordings: [[UInt64]] = []
  /// Whether renders hand owners their previous tokens. Only an `EquatableView` needs it (a reused result keeps
  /// its nested owners' tokens), and the per-path bookkeeping costs a list render more than stable tokens save,
  /// so it starts with the first result an `EquatableView` keeps.
  private var reusesOwners = false
  /// The entries of pooled tokens, so an `EquatableView` that reuses its content can hand its nested owners
  /// their entries back unchanged (`_claim`).
  private var pooledEntries: [UInt64: Entry] = .init()
  /// The enclosing owner and the aliasable mark a pooled entry had, kept beside it in tables of the same types as
  /// `outerOwners` and `aliasableOwners` (Embedded Swift emits the hashed-collection code once per key and value type).
  private var pooledOuterOwners: [UInt64: UInt64] = .init()
  private var pooledAliasableOwners: Set<UInt64> = []
  /// `EquatableView` results by structural path: the content value, the environment entries the content read
  /// (with their stamps), the node it rendered and the owners inside it.
  private var memoValues = _TypedValueStorage<_FiberPath>()
  private var memos: [_FiberPath: (reads: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)], node: _RenderNode, owners: [UInt64])] = .init()
  private let memoLimit = 8192
  /// The last render of each view that compares its inputs (`View._comparesInputs`), by path: its value, the environment
  /// entries its render read, and the node. A pass that renders the view's parent again reuses the node when nothing the
  /// view depends on changed (`_reusedView`). The value is held by a renderer (`_ViewRenderer`), which keeps the type
  /// checks and the comparison in the one class that is generic over the view.
  private var viewMemoValues: [_FiberPath: _AnyViewRenderer] = .init()
  private var viewMemos: [_FiberPath: (reads: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)], node: _RenderNode, since: UInt64)] = .init()
  /// Counts the renders of an owner on its own (`_render`), while views are remembered: `ownRenders` holds each
  /// owner's last. A remembered node is a copy of what the view returned, which such a render does not update, so a
  /// memo with an owner rendered after it is not used.
  private(set) var _ownRenderSequence: UInt64 = 0
  private var ownRenders: [UInt64: UInt64] = .init()
  private let viewMemoLimit = 4096

  public init() {}

  @_spi(Renderer) public func _register(
    context: _RenderContext,
    render: @escaping (_RenderContext) -> _RenderNode
  ) -> UInt64 {
    // Zero is reserved as "no owner" by the observation protocol. Never wrap
    // and let an old owner token alias a newly registered Swift closure.
    let token = reusableByPath.isEmpty ? _allocateToken() : _reusableToken(at: context._fiberPath)
    var base = context
    base._renderOwnerToken = nil
    // Entries are owned by this registry. Keeping self in their context would
    // form registry -> entry -> context -> registry and retain model/state
    // storage after the FiberTree is released.
    base._renderOwnerRegistry = nil
    entries[token] = Entry(context: base, render: render)
    for index in recordings.indices { recordings[index].append(token) }
    return token
  }

  /// Starts recording the owners registered from now on, until `_endRecordingRegistrations`.
  @_spi(Renderer) public func _beginRecordingRegistrations() { recordings.append([]) }

  /// Stops the innermost recording and returns the tokens it registered.
  @_spi(Renderer) public func _endRecordingRegistrations() -> [UInt64] { recordings.popLast() ?? [] }

  /// Retires the given owners (those a discarded render registered) unless a Fiber reclaimed them.
  @_spi(Renderer) public func _retireRegistrations(_ tokens: [UInt64]) {
    for token in tokens { _remove(token) }
  }

  /// Kept out of line: `_register` runs at every level of a view tree, and inlining this dictionary work grew each
  /// level's stack frame enough for a deep tree to overflow WebKit's WebAssembly stack.
  @inline(never) private func _reusableToken(at path: _FiberPath) -> UInt64 {
    guard let reusable = reusableByPath[path] else { return _allocateToken() }
    let occurrence = reusedCount[path, default: 0]
    reusedCount[path] = occurrence + 1
    guard occurrence < reusable.count, entries[reusable[occurrence]] == nil else { return _allocateToken() }
    reclaimed.insert(reusable[occurrence])
    return reusable[occurrence]
  }

  private func _allocateToken() -> UInt64 {
    precondition(nextToken < UInt64.max, "Render owner identity space exhausted")
    let token = nextToken
    nextToken += 1
    return token
  }

  /// Starts rendering `tokens`' owners again: their entries leave the table and wait, by path, for the owner
  /// that registers at the same path during the render. `_endReuse` retires the ones nobody claimed.
  @_spi(Renderer) public func _beginReuse(_ tokens: some Sequence<UInt64>) {
    guard reusesOwners else { return }
    var pooled: [(token: UInt64, path: _FiberPath)] = []
    for token in tokens {
      guard let entry = entries.removeValue(forKey: token) else { continue }
      pooledEntries[token] = entry
      pooledOuterOwners[token] = outerOwners.removeValue(forKey: token)
      if aliasableOwners.remove(token) != nil { pooledAliasableOwners.insert(token) } else { pooledAliasableOwners.remove(token) }
      pooled.append((token, entry.context._fiberPath))
    }
    // Tokens grow in registration order, so sorting restores each path's registration sequence.
    pooled.sort { $0.token < $1.token }
    for item in pooled { reusableByPath[item.path, default: []].append(item.token) }
    reusedCount.removeAll(keepingCapacity: true)
    reclaimed.removeAll(keepingCapacity: true)
  }

  /// `_beginReuse` for every owner, as a full render from the root does.
  /// Without reuse (see `reusesOwners`) every owner is retired and registers afresh.
  @_spi(Renderer) public func _beginReuseAll() {
    guard reusesOwners else { return _removeAll() }
    _beginReuse(Array(entries.keys))
    outerOwners.removeAll(keepingCapacity: true)
    innerOwners.removeAll(keepingCapacity: true)
    aliasableOwners.removeAll(keepingCapacity: true)
  }

  /// The start of a pass from the root. While views remember what they rendered (`_reusedView`) the owners stay
  /// registered, so a render reused in this pass finds the ones below it, and the pass retires what the Fibers gave up;
  /// returns true then. Otherwise every owner is retired or pooled as before (`_beginReuseAll`).
  @_spi(Renderer) public func _beginRootPass() -> Bool {
    if !reusesOwners && !viewMemos.isEmpty { return true }
    _beginReuseAll()
    return false
  }

  /// Retires the tokens no owner claimed during the render.
  @_spi(Renderer) public func _endReuse() {
    for (path, tokens) in reusableByPath {
      for token in tokens where entries[token] == nil {
        rememberRetiredPath(token, path: path)
        innerOwners.removeValue(forKey: token)
      }
    }
    reusableByPath.removeAll(keepingCapacity: true)
    reusedCount.removeAll(keepingCapacity: true)
    pooledEntries.removeAll(keepingCapacity: true)
    pooledOuterOwners.removeAll(keepingCapacity: true)
    pooledAliasableOwners.removeAll(keepingCapacity: true)
  }

  /// Gives pooled `tokens` their entries back, as their owners are mounted again without rendering. Fails
  /// (claiming nothing) when one of them is neither pooled nor registered: its owner was retired.
  func _claim(_ tokens: [UInt64]) -> Bool {
    for token in tokens where entries[token] == nil && pooledEntries[token] == nil { return false }
    for token in tokens {
      guard let pooled = pooledEntries.removeValue(forKey: token) else { continue }
      reclaimed.insert(token)
      entries[token] = pooled
      if let outer = pooledOuterOwners.removeValue(forKey: token) { outerOwners[token] = outer }
      if pooledAliasableOwners.remove(token) != nil { aliasableOwners.insert(token) }
    }
    return true
  }

  /// The node `EquatableView` rendered at `path` for an equal `content`, when every environment entry that
  /// render read still holds the same stamp and its nested owners are still mounted.
  func _memoized<Content: Equatable>(at path: _FiberPath, content: Content, environment: EnvironmentValues) -> (node: _RenderNode, reads: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)])? {
    guard let memo = memos[path], let previous: Content = memoValues.value(for: path, as: Content.self), previous == content else { return nil }
    for read in memo.reads where environment._stamp(for: read.key) != read.stamp { return nil }
    guard _claim(memo.owners) else {
      memos.removeValue(forKey: path)
      return nil
    }
    return (memo.node, memo.reads)
  }

  func _memoize<Content: Equatable>(at path: _FiberPath, content: Content, reads: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)], node: _RenderNode) {
    reusesOwners = true
    if memos.count >= memoLimit && memos[path] == nil {
      memos.removeAll(keepingCapacity: true)
      memoValues = _TypedValueStorage<_FiberPath>()
    }
    var owners: [UInt64] = []
    func collect(_ current: _RenderNode) {
      if let token = current._renderOwnerToken { owners.append(token) }
      for child in current.children { collect(child) }
    }
    collect(node)
    memoValues.set(content, for: path)
    memos[path] = (reads, node, owners)
  }

  /// What the view rendered at `path` last time, when it is still what it would render: its inputs are the same
  /// (`View._sameInputs`), every environment entry it read is unchanged, and every owner below it is still registered and
  /// read nothing that changed since. The owners keep what they read through this pass (`StateStore._keepOwnerReads`), so
  /// their state still reaches them, and their tokens. A copy of the remembered node is returned: what wraps the view
  /// (its modifiers) writes into the node it gets, which must stay as the view returned it.
  ///
  /// `sameInputs` tells whether the renderer holding the remembered value holds a value of the new one's type with the
  /// same inputs (`_ViewRenderer.hasSameInputs`); it runs only when there is a memo at `path`.
  func _reusedView(at path: _FiberPath, context: _RenderContext, sameInputs: (_AnyViewRenderer) -> Bool) -> _RenderNode? {
    guard let memo = viewMemos[path], let holder = viewMemoValues[path], sameInputs(holder) else { return nil }
    // A GeometryReader below has been drawn for a new size since (`StateStore._forgetViews(above:)`): what was remembered
    // holds its old drawing, and an owner's own render does not always tell (a custom Layout renders its subviews again to
    // measure them, under other owners). Food Truck's tiles kept donuts drawn for 23 points in 155-point boxes.
    let stateStore = context.stateStore
    if !stateStore._staleViewPaths.isEmpty, stateStore._staleViewPaths.remove(path) != nil {
      viewMemos.removeValue(forKey: path)
      return nil
    }
    for read in memo.reads where context.environment._stamp(for: read.key) != read.stamp { return nil }
    let remembered = memo.node
    var owners = Set<UInt64>()
    var pending = [remembered]
    while let node = pending.popLast() {
      if let token = node._renderOwnerToken { _ownersReturning(token, into: &owners) }
      pending.append(contentsOf: node.children)
    }
    let store = context.stateStore
    for token in owners {
      guard entries[token] != nil || pooledEntries[token] != nil else {
        viewMemos.removeValue(forKey: path)
        return nil
      }
      if store._ownerIsDirty(token) { return nil }
      if let rendered = ownRenders[token], rendered > memo.since {
        viewMemos.removeValue(forKey: path)
        return nil
      }
    }
    let tokens = Array(owners)
    guard let copy = remembered._reuseSnapshot() else { return nil }
    guard _claim(tokens) else {
      viewMemos.removeValue(forKey: path)
      return nil
    }
    store._keepOwnerReads(tokens)
    // An enclosing view depends on what this one read, though it was not read again.
    EnvironmentValues._readRecorder?.merge(memo.reads)
    return copy
  }

  /// Remembers what the value `holder` holds rendered at `path` and the environment entries it read (`_reusedView`).
  func _rememberView(at path: _FiberPath, holder: _AnyViewRenderer, reads: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)], node: _RenderNode, since: UInt64) {
    // Not `reusesOwners`: handing owners their tokens back by path costs a deep subtree a comparison of its whole path
    // per owner (a thousand nested navigation levels mounted in 19 s instead of 4). A pass that renders a subtree again
    // keeps the owners below it registered, so a render reused there still finds them (`_claim`); a pass from the root
    // retires them all, and then nothing is reused.
    if viewMemos.count >= viewMemoLimit && viewMemos[path] == nil {
      viewMemos.removeAll(keepingCapacity: true)
      viewMemoValues = .init()
    }
    viewMemoValues[path] = holder
    viewMemos[path] = (reads, node, since)
  }

  @_spi(Renderer) public func _render(_ token: UInt64) -> _RenderNode? {
    guard let entry = entries[token] else { return nil }
    if !viewMemos.isEmpty {
      _ownRenderSequence &+= 1
      ownRenders[token] = _ownRenderSequence
    }
    var context = entry.context
    // Restore only for the synchronous render so nested owners still register.
    context._renderOwnerRegistry = self
    context._renderOwnerToken = token
    // A retained render starts outside any enclosing view's render: an owner that is not an erased view (a tab's
    // `ForEach` element, a modifier or reader boundary) evaluates the views it builds with no environment and no
    // state scope, so an `@Environment(Model.self)` they read has nowhere to resolve from and traps. Give it the
    // environment and scope the first render had from the enclosing view.
    let ownScope = StateRuntime.scope == nil ? _enterRenderScope(context, viewTag: "owner") : nil
    let node = entry.render(context)
    if let ownScope { _exitRenderScope(ownScope) }
    // As in the first render: when this owner returns a node an inner owner returned (the root's body
    // is a view with its own `@State`), the node carries this token from now on, so readers recorded
    // under the inner token must route here. Without the chain they look unmounted, and a batch that
    // also invalidates another owner would drop their writes.
    if let inner = node._renderOwnerToken { _recordOuterOwner(inner, token) }
    node._renderOwnerToken = token
    _recordStateScopePath(node, path: entry.context._fiberPath)
    // Keep the latest context/closure.  This is important when a targeted
    // render changes the value view captured by nested AnyViews.
    entries[token] = Entry(context: entry.context, render: entry.render)
    return node
  }

  @_spi(Renderer) public func _contains(_ token: UInt64) -> Bool {
    entries[token] != nil
  }

  /// Renders an owner's closure without registering owners, updating its entry
  /// or running effects. The caller compares the result and discards it.
  @_spi(Renderer) public func _renderSpeculative(_ token: UInt64) -> _RenderNode? {
    guard let entry = entries[token] else { return nil }
    var context = entry.context
    context._renderOwnerRegistry = nil
    context._renderOwnerToken = nil
    context._speculative = true
    let ownScope = StateRuntime.scope == nil ? _enterRenderScope(context, viewTag: "owner") : nil
    let node = entry.render(context)
    if let ownScope { _exitRenderScope(ownScope) }
    return node
  }

  /// Marks an owner whose invalidations must reach its enclosing owner's
  /// Fiber when an enclosing owner returns the same node (a GeometryReader).
  @_spi(Renderer) public func _markAliasable(_ token: UInt64) {
    aliasableOwners.insert(token)
  }

  @_spi(Renderer) public func _recordOuterOwner(_ inner: UInt64, _ outer: UInt64) {
    guard inner != outer else { return }
    if let previous = innerOwners[outer], previous != inner, outerOwners[previous] == outer { _remove(previous) }
    innerOwners[outer] = inner
    outerOwners[inner] = outer
    // Enclosing owners that also return this node keep extending the chain.
    aliasableOwners.insert(outer)
  }

  /// `token` and the inner owners whose node it returned, and theirs: every owner a render of `token`'s node made.
  @_spi(Renderer) public func _ownersReturning(_ token: UInt64, into result: inout Set<UInt64>) {
    var current = token
    while result.insert(current).inserted, let inner = innerOwners[current], outerOwners[inner] == current { current = inner }
  }

  /// The outermost owner that returned the same node as `token`, or `token`.
  @_spi(Renderer) public func _outermostOwner(of token: UInt64) -> UInt64 {
    var current = token
    var hops = 0
    while let outer = outerOwners[current], outer != current, hops < 16 {
      current = outer
      hops += 1
    }
    return current
  }

  /// Stable structural path for routing a retained observation whose token
  /// was replaced by a recent render but whose logical view identity remains
  /// mounted.
  @_spi(Renderer) public func _ownerPath(_ token: UInt64) -> _FiberPath? {
    entries[token]?.context._fiberPath ?? retiredPaths[token]
  }

  /// Retires `token`, and the inner owners whose node it returned (they go with the node).
  @_spi(Renderer) public func _remove(_ token: UInt64) {
    var pending = [token]
    while let current = pending.popLast() {
      // The Fiber releasing it held the token before the last render, which gave it to a new owner.
      guard !reclaimed.contains(current) else { continue }
      ownRenders.removeValue(forKey: current)
      if let outer = outerOwners.removeValue(forKey: current), innerOwners[outer] == current { innerOwners.removeValue(forKey: outer) }
      if let inner = innerOwners.removeValue(forKey: current), outerOwners[inner] == current { pending.append(inner) }
      aliasableOwners.remove(current)
      guard let entry = entries.removeValue(forKey: current) else { continue }
      rememberRetiredPath(current, path: entry.context._fiberPath)
    }
  }

  /// Live literals: forgets what every view rendered, so the next pass from the root renders each of them
  /// again; owners and their state stay.
  @_spi(Renderer) public func _forgetRenderedViews() {
    memos.removeAll(keepingCapacity: true)
    memoValues = _TypedValueStorage<_FiberPath>()
    viewMemos.removeAll(keepingCapacity: true)
    viewMemoValues.removeAll(keepingCapacity: true)
  }

  @_spi(Renderer) public func _removeAll(keepingCapacity: Bool = true) {
    reclaimed.removeAll(keepingCapacity: keepingCapacity)
    pooledEntries.removeAll(keepingCapacity: keepingCapacity)
    pooledOuterOwners.removeAll(keepingCapacity: keepingCapacity)
    pooledAliasableOwners.removeAll(keepingCapacity: keepingCapacity)
    memos.removeAll(keepingCapacity: keepingCapacity)
    memoValues = _TypedValueStorage<_FiberPath>()
    viewMemos.removeAll(keepingCapacity: keepingCapacity)
    viewMemoValues = .init()
    ownRenders.removeAll(keepingCapacity: keepingCapacity)
    outerOwners.removeAll(keepingCapacity: keepingCapacity)
    innerOwners.removeAll(keepingCapacity: keepingCapacity)
    aliasableOwners.removeAll(keepingCapacity: keepingCapacity)
    for (token, entry) in entries {
      rememberRetiredPath(token, path: entry.context._fiberPath)
    }
    entries.removeAll(keepingCapacity: keepingCapacity)
    if !keepingCapacity {
      retiredPaths.removeAll(keepingCapacity: false)
      retiredPathTokens.removeAll(keepingCapacity: false)
      retiredPathCursor = 0
    }
  }

  @MainActor private func rememberRetiredPath(_ token: UInt64, path: _FiberPath) {
    guard retiredPaths[token] == nil else { return }
    if retiredPathTokens.count < retiredPathLimit {
      retiredPathTokens.append(token)
    } else {
      let evicted = retiredPathTokens[retiredPathCursor]
      retiredPaths.removeValue(forKey: evicted)
      retiredPathTokens[retiredPathCursor] = token
      retiredPathCursor = (retiredPathCursor + 1) % retiredPathLimit
    }
    retiredPaths[token] = path
  }

  /// Rebinds owners whose environment is still the root environment. Owners
  /// below a `.environment(...)` modifier carry a different revision and are
  /// deliberately excluded: refreshing one of those owners without replaying
  /// its ancestor modifiers could expose the wrong inherited value.
  @_spi(Renderer) public func _rebindEnvironment(
    from oldRevision: UInt64,
    to environment: EnvironmentValues
  ) -> Set<UInt64> {
    var safeOwners: Set<UInt64> = []
    let candidates = entries.compactMap { token, entry in
      // A local `.environment` modifier can happen to produce the same
      // numeric revision as the root environment.  Revision equality alone
      // is therefore not proof that this owner inherits the root value.
      entry.context.environment._revision == oldRevision &&
        !entry.context.environment._hasLocalOverride ? token : nil
    }
    for token in candidates {
      guard var updated = entries[token] else { continue }
      updated.context.environment = environment
      entries[token] = updated
      safeOwners.insert(token)
    }
    return safeOwners
  }

  @_spi(Renderer) public func _allContextsUseEnvironmentRevision(_ revision: UInt64) -> Bool {
    entries.values.allSatisfy {
      $0.context.environment._revision == revision &&
        !$0.context.environment._hasLocalOverride
    }
  }
}

/// Primitive views use `Never` as their body and provide their own renderer.
extension Never: View {
  public typealias Body = Never
  public func _render(in context: _RenderContext) -> _RenderNode { .empty() }
}

/// What an `AnyView` renders. A class with an overridden `render` rather than
/// a stored closure because erased boundaries sit on the render recursion: a
/// call through a closure adds the closure's specialization, reabstraction
/// and partial-apply frames, where a class method adds one, and WebKit runs a
/// Worker's WebAssembly on a stack small enough that those frames bound how
/// deep a view tree renders.
class _AnyViewRenderer {
  @MainActor func render(_ context: _RenderContext) -> _RenderNode { .empty() }
  /// Whether the view compares its inputs, so that what it rendered can be reused (`_RenderOwnerRegistry._reusedView`).
  @MainActor var comparesInputs: Bool { false }
  /// What the view rendered at `path` last time, when it is still what it would render.
  @MainActor func reusedRender(at path: _FiberPath, context: _RenderContext, registry: _RenderOwnerRegistry) -> _RenderNode? { nil }
  /// Remembers what the view rendered at `path` and the environment entries it read.
  @MainActor func rememberRender(_ node: _RenderNode, reads: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)], at path: _FiberPath, since: UInt64, registry: _RenderOwnerRegistry) {}
}

/// Renders a concrete view in its own environment and state scope, tagging
/// the node with the view's type name.
private final class _ViewRenderer<V: View>: _AnyViewRenderer {
  private let view: V
  private let tag: String

  init(_ view: V, tag: String) {
    self.view = view
    self.tag = tag
  }

  @MainActor override func render(_ context: _RenderContext) -> _RenderNode {
    let saved = _enterRenderScope(context, viewTag: tag)
    let node = view._render(in: context)
    _exitRenderScope(saved)
    node._postDescriptor(tag)
    return node
  }

  @MainActor override var comparesInputs: Bool { V._comparesInputs }

  @MainActor override func reusedRender(at path: _FiberPath, context: _RenderContext, registry: _RenderOwnerRegistry) -> _RenderNode? {
    registry._reusedView(at: path, context: context) { remembered in _ViewRenderer<V>.hasSameInputs(remembered, as: view) }
  }

  @MainActor override func rememberRender(_ node: _RenderNode, reads: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)], at path: _FiberPath, since: UInt64, registry: _RenderOwnerRegistry) {
    // The view is immutable, so the renderer itself holds the value the memo was made for.
    registry._rememberView(at: path, holder: self, reads: reads, node: node, since: since)
  }

  /// Whether `remembered` holds a value of type `V` with the inputs of `value` (`View._sameInputs`).
  @MainActor static func hasSameInputs(_ remembered: _AnyViewRenderer, as value: V) -> Bool {
    guard let remembered = remembered as? _ViewRenderer<V> else { return false }
    return V._sameInputs(remembered.view, value)
  }
}

/// Forms a view from a builder on every render, then renders it like
/// `_ViewRenderer`.
private final class _ContentRenderer<Content: View>: _AnyViewRenderer {
  private let content: () -> Content

  init(_ content: @escaping () -> Content) {
    self.content = content
  }

  @MainActor override func render(_ context: _RenderContext) -> _RenderNode {
    let saved = _enterRenderScope(context, viewTag: "content")
    let view = content()
    built = view
    let node = view._render(in: context)
    _exitRenderScope(saved)
    node._postDescriptor(_swiftUIWebTypeName(Content.self))
    return node
  }

  /// The view the last render built, for `rememberRender`: a `ForEach` row is built from its element on every render.
  /// (A render through Observation tracking builds its own, and `rememberRender` builds it again.)
  private var built: Content?

  @MainActor override var comparesInputs: Bool { Content._comparesInputs }

  @MainActor override func reusedRender(at path: _FiberPath, context: _RenderContext, registry: _RenderOwnerRegistry) -> _RenderNode? {
    let saved = _enterRenderScope(context, viewTag: "content")
    let view = content()
    _exitRenderScope(saved)
    return registry._reusedView(at: path, context: context) { remembered in _ViewRenderer<Content>.hasSameInputs(remembered, as: view) }
  }

  @MainActor override func rememberRender(_ node: _RenderNode, reads: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)], at path: _FiberPath, since: UInt64, registry: _RenderOwnerRegistry) {
    let value: Content
    if let built {
      value = built
    } else {
      value = content()
    }
    // A renderer of its own holds the value: this one builds a new view on every render. It never renders, so it has no tag.
    registry._rememberView(at: path, holder: _ViewRenderer(value, tag: ""), reads: reads, node: node, since: since)
  }
}

/// A view that renders as its own owner boundary, so a retained render re-runs
/// all of `_renderOwnerBoundary(in:)` (modifier post-processing, a reader's
/// host measurement) rather than only the content below it.
package protocol _OwnerBoundaryContent {
  @MainActor func _renderOwnerBoundary(in context: _RenderContext) -> _RenderNode
}

/// Renders an `_OwnerBoundaryContent` value. A generic class instead of an
/// `_ownerBoundary` closure keeps the boundary to one frame on the render
/// recursion (see `_AnyViewRenderer`).
private final class _OwnerBoundaryRenderer<Owner: _OwnerBoundaryContent>: _AnyViewRenderer {
  private let owner: Owner

  init(_ owner: Owner) {
    self.owner = owner
  }

  @MainActor override func render(_ context: _RenderContext) -> _RenderNode { owner._renderOwnerBoundary(in: context) }
}

/// Runs arbitrary renderer code as an owner boundary.
private final class _ClosureRenderer: _AnyViewRenderer {
  private let body: @MainActor (_RenderContext) -> _RenderNode

  init(_ body: @escaping @MainActor (_RenderContext) -> _RenderNode) {
    self.body = body
  }

  @MainActor override func render(_ context: _RenderContext) -> _RenderNode { body(context) }
}

/// Gives the node another renderer returns a builder key: always when
/// `overriding`, otherwise only when the node has none. Used when the erased
/// view already carries a key (`AnyView._withKey` fuses the first key into the
/// view itself, because this wrapper costs a frame on the render recursion).
private final class _KeyedRenderer: _AnyViewRenderer {
  private let base: _AnyViewRenderer
  private let key: _FiberKey
  private let overriding: Bool

  init(_ base: _AnyViewRenderer, key: _FiberKey, overriding: Bool) {
    self.base = base
    self.key = key
    self.overriding = overriding
  }

  @MainActor override func render(_ context: _RenderContext) -> _RenderNode {
    let node = base.render(context)
    node._postKey(key, overriding: overriding)
    return node
  }

  // The key is on the node the view rendered, so a reused node carries it already.
  @MainActor override var comparesInputs: Bool { base.comparesInputs }

  @MainActor override func reusedRender(at path: _FiberPath, context: _RenderContext, registry: _RenderOwnerRegistry) -> _RenderNode? {
    base.reusedRender(at: path, context: context, registry: registry)
  }

  @MainActor override func rememberRender(_ node: _RenderNode, reads: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)], at path: _FiberPath, since: UInt64, registry: _RenderOwnerRegistry) {
    base.rememberRender(node, reads: reads, at: path, since: since, registry: registry)
  }
}

/// The builder key an `AnyView` gives the node it renders. A class so that copying the view, which every render does,
/// is one retain rather than a copy of the key.
final class _BuilderKey {
  private let key: _FiberKey
  private let overriding: Bool
  init(_ key: _FiberKey, overriding: Bool) { self.key = key; self.overriding = overriding }
  @MainActor @inline(__always) func apply(to node: _RenderNode) {
    if overriding || node.key == nil { node.key = key }
  }
  /// `apply(to:)` for a node that may stand in for a render that has not run (see `_PendingRender`).
  @MainActor @inline(__always) func post(to node: _RenderNode) {
    if node._isPendingRender { node._keep(.builderKey(self)) } else { apply(to: node) }
  }
}

/// A type-erased view. Erasure happens at view-builder boundaries only; the
/// runtime Fiber graph retains stable keys and concrete render metadata.
///
/// Like SwiftUI's, the struct and its initializers are nonisolated so any context can erase a
/// view. The retained renderers are main-actor closures; the erased view is only ever rendered
/// by the main-actor runtime, so the view they capture is never touched from another actor.
public nonisolated struct AnyView: View {
  public typealias Body = Never
  private let renderer: _AnyViewRenderer
  private let observationBodyRendererFactory: (@MainActor (_RenderContext) -> @MainActor (_RenderContext) -> _RenderNode)?
  /// An unowned boundary renders inline: its state and observation reads
  /// belong to the enclosing owner, which is the one that re-renders it.
  private var registersOwner = true
  /// The builder key `_withKey` gave this boundary, applied to the node it renders (see `_KeyedRenderer`).
  private var builderKey: _BuilderKey?

  /// Gives `node` the builder key, as `_KeyedRenderer` does.
  @inline(__always) @MainActor private func applyBuilderKey(_ node: _RenderNode) {
    if let builderKey { builderKey.post(to: node) }
  }

  /// Erases `view` without registering a retained owner of its own.
  @_spi(Renderer) public static func _unowned<V: View>(_ view: V) -> AnyView {
    var erased = AnyView(view)
    erased.registersOwner = false
    return erased
  }

  /// An owner boundary around arbitrary renderer code. A retained render of
  /// the boundary re-runs all of `render`, including any node post-processing
  /// it does after rendering children.
  @_spi(Renderer) public init(_ownerBoundary render: @escaping @MainActor (_RenderContext) -> _RenderNode) {
    renderer = _ClosureRenderer(render)
    observationBodyRendererFactory = nil
  }

  /// The owner boundary of `owner`; see `_OwnerBoundaryContent`.
  package init<Owner: _OwnerBoundaryContent>(_ownerBoundaryOf owner: Owner) {
    renderer = _OwnerBoundaryRenderer(owner)
    observationBodyRendererFactory = nil
  }

  public nonisolated init<V: View>(_ view: V) {
    // The type name is a pure function of `V`; computing it once here rather
    // than on every render keeps the per-type closure to the `_render` call.
    let tag = _swiftUIWebTypeName(V.self)
    // SAFETY: the main-actor renderer and closures below are the only users of `view`, and they run on the main actor.
    nonisolated(unsafe) let view = view
    renderer = _ViewRenderer(view, tag: tag)
    if V.Body.self == Never.self {
      observationBodyRendererFactory = nil
    } else {
      observationBodyRendererFactory = { context in
        let saved = _enterRenderScope(context, viewTag: tag)
        let renderer = _makeObservationBodyRenderer(view)
        _exitRenderScope(saved)
        return _describedRenderer(renderer, tag: tag)
      }
    }
  }

  @_alwaysEmitIntoClient
  public nonisolated init<V: View>(erasing view: V) { self.init(view) }

  package init(@ViewBuilder content: @escaping () -> some View) {
    // SAFETY: only the main-actor renderer and closure below call `content`.
    nonisolated(unsafe) let content = content
    renderer = _ContentRenderer(content)
    observationBodyRendererFactory = { context in
      let saved = _enterRenderScope(context, viewTag: "content")
      let view = content()
      let renderer = _describedRenderer(_makeObservationBodyRenderer(view), tag: _swiftUIWebTypeName(Swift.type(of: view)))
      _exitRenderScope(saved)
      return renderer
    }
  }

  private init(
    renderer: _AnyViewRenderer,
    observationBodyRendererFactory: (@MainActor (_RenderContext) -> @MainActor (_RenderContext) -> _RenderNode)?
  ) {
    self.renderer = renderer
    self.observationBodyRendererFactory = observationBodyRendererFactory
  }

  /// Builder identity belongs to every evaluation of this boundary, including
  /// retained owner renders that do not rerun the enclosing if/ForEach.
  @MainActor func _withKey(_ key: _FiberKey, overriding: Bool = false) -> AnyView {
    let applyKey: @MainActor (_RenderNode) -> _RenderNode = { node in
      node._postKey(key, overriding: overriding)
      return node
    }
    let factory: (@MainActor (_RenderContext) -> @MainActor (_RenderContext) -> _RenderNode)?
    if let original = observationBodyRendererFactory {
      factory = { context in
        let renderer = original(context)
        return { applyKey(renderer($0)) }
      }
    } else {
      factory = nil
    }
    guard builderKey == nil else {
      return AnyView(
        renderer: _KeyedRenderer(renderer, key: key, overriding: overriding),
        observationBodyRendererFactory: factory
      )
    }
    var keyed = AnyView(renderer: renderer, observationBodyRendererFactory: factory)
    keyed.builderKey = _BuilderKey(key, overriding: overriding)
    return keyed
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    guard registersOwner, let registry = context._renderOwnerRegistry else {
      return renderKeyed(context)
    }
    if renderer.comparesInputs, _ViewReuse.enabled, !context._speculative {
      return _renderReusing(context, registry: registry)
    }
    return _renderOwned(context, registry: registry)
  }

  /// A view that compares its inputs (`View._comparesInputs`): what it rendered last time when that still holds,
  /// otherwise a render that records the environment entries it reads, remembered unless it handed something to an
  /// ancestor (`_renderRegistersWithAncestors`). A render that left part of itself for the loop that drives the pass
  /// (`_RenderStaging`, a deep tree) is remembered once that part has run too, what it reads included. Out of line, so
  /// that the frame of every other boundary stays as it was.
  @inline(never) @MainActor private func _renderReusing(_ context: _RenderContext, registry: _RenderOwnerRegistry) -> _RenderNode {
    let path = context._fiberPath
    if let reused = renderer.reusedRender(at: path, context: context, registry: registry) { return reused }
    let since = registry._ownRenderSequence
    let recorder = _EnvironmentReadRecorder(base: context.environment)
    let enclosing = EnvironmentValues._readRecorder
    EnvironmentValues._readRecorder = recorder
    let deferrals = _RenderStaging.deferrals
    let node = _renderOwned(context, registry: registry)
    EnvironmentValues._readRecorder = enclosing
    // A copy as the view returned it: what wraps the view writes into the node next.
    if _RenderStaging.deferrals == deferrals {
      enclosing?.merge(recorder)
      if !recorder.untracked, let snapshot = node._reuseSnapshot() {
        renderer.rememberRender(snapshot, reads: recorder.reads, at: path, since: since, registry: registry)
      }
      return node
    }
    let renderer = self.renderer
    let snapshot = _ReuseSnapshot()
    _RenderStaging.snapshot(of: node) { snapshot.node = $0 }
    _RenderStaging.settled {
      enclosing?.merge(recorder)
      if !recorder.untracked, let node = snapshot.node {
        renderer.rememberRender(node, reads: recorder.reads, at: path, since: since, registry: registry)
      }
    }
    return node
  }

  /// Registers this boundary's owner and renders its view under it.
  @inline(__always) @MainActor private func _renderOwned(_ context: _RenderContext, registry: _RenderOwnerRegistry) -> _RenderNode {
    #if hasFeature(Embedded)
    // Every erased boundary sits on the render recursion, so this frame stays small: registering the owner and
    // closing it out happen in separate functions that are gone from the stack while the content renders.
    let token = _registerEmbeddedOwner(renderer, key: builderKey, context: context, registry: registry)
    var ownedContext = context
    ownedContext._renderOwnerToken = token
    let node = renderKeyed(ownedContext)
    _finishEmbeddedOwner(node, token: token, context: context, registry: registry)
    return node
    #else
    // Retained owner renders must re-establish Observation tracking. The
    // original implementation registered the raw render closure, which meant
    // the first mutation targeted a row correctly but subsequent mutations of
    // that same row had no one-shot callback left to fire. Keep the renderer
    // closure behind the owner registry, but wrap every retained invocation in
    // the same tracking scope used by the initial render.
    let ownerToken = _RenderOwnerTokenBox()
    let retainedRenderer = renderer
    let retainedObservationFactory = observationBodyRendererFactory
    // The owner registry retains the render closure. Capture it weakly so the
    // closure cannot keep the registry alive through its Observation callback
    // after an owner has been removed.
    func retainedOwnerRender(_ targetContext: _RenderContext, registry currentRegistry: _RenderOwnerRegistry?) -> _RenderNode {
      var ownedTargetContext = targetContext
      ownedTargetContext._renderOwnerToken = ownerToken.value
      #if canImport(Observation) && !hasFeature(Embedded)
      if !targetContext._speculative, #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
        let store = targetContext.stateStore
        if let retainedObservationFactory {
          let bodyRenderer = withObservationTracking({
            retainedObservationFactory(ownedTargetContext)
          }, onChange: { [weak store, weak registry] in
            // SAFETY: Observation reports a model change synchronously on the thread that wrote it, which is
            // the main actor for every model a view reads; the registry and store are main-actor isolated.
            _assumeMainActor {
              guard currentRegistry?._contains(ownerToken.value) == true else { return }
              store?._ownerObservationDidChange(ownerToken.value)
            }
          })
          return bodyRenderer(ownedTargetContext)
        }
        return withObservationTracking({
          self.renderKeyed(ownedTargetContext)
        }, onChange: { [weak store, weak registry] in
          // SAFETY: Observation reports a model change synchronously on the thread that wrote it, which is
          // the main actor for every model a view reads; the registry and store are main-actor isolated.
          _assumeMainActor {
            guard currentRegistry?._contains(ownerToken.value) == true else { return }
            store?._ownerObservationDidChange(ownerToken.value)
          }
        })
      }
      #endif
      return self.renderKeyed(ownedTargetContext)
    }
    #if hasFeature(Embedded)
    let token = registry._register(context: context) { targetContext in
      retainedOwnerRender(targetContext, registry: registry)
    }
    #else
    let token = registry._register(context: context) { [weak registry] targetContext in
      retainedOwnerRender(targetContext, registry: registry)
    }
    #endif
    ownerToken.value = token
    var ownedContext = context
    ownedContext._renderOwnerToken = token
    let node: _RenderNode
    #if canImport(Observation) && !hasFeature(Embedded)
    if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
      let store = context.stateStore
      if let observationBodyRendererFactory {
        let bodyRenderer = withObservationTracking({
          observationBodyRendererFactory(ownedContext)
        }, onChange: { [weak store, weak registry] in
          // Observation callbacks are one-shot, but a view owner can
          // disappear before the observed model changes (for example after a
          // root update replaces a branch). Do not enqueue a stale owner
          // token; otherwise a later model write would conservatively fall
          // back to a whole-tree render even though the original scope is no
          // longer mounted.
          // SAFETY: Observation reports a model change synchronously on the thread that wrote it, which is
          // the main actor for every model a view reads; the registry and store are main-actor isolated.
          _assumeMainActor {
            guard registry?._contains(token) == true else { return }
            store?._ownerObservationDidChange(token)
          }
        })
        node = _renderBody(bodyRenderer, ownedContext)
      } else {
        node = withObservationTracking({
          self.renderKeyed(ownedContext)
        }, onChange: { [weak store, weak registry] in
          // Observation callbacks are one-shot, but a view owner can
          // disappear before the observed model changes (for example after a
          // root update replaces a branch). Do not enqueue a stale owner
          // token; otherwise a later model write would conservatively fall
          // back to a whole-tree render even though the original scope is no
          // longer mounted.
          // SAFETY: Observation reports a model change synchronously on the thread that wrote it, which is
          // the main actor for every model a view reads; the registry and store are main-actor isolated.
          _assumeMainActor {
            guard registry?._contains(token) == true else { return }
            store?._ownerObservationDidChange(token)
          }
        })
      }
    } else {
      node = renderKeyed(ownedContext)
    }
    #else
    node = renderKeyed(ownedContext)
    #endif
    _postFinishOwner(node, token: token, path: context._fiberPath, registry: registry)
    return node
    #endif
  }

  @inline(__always) @MainActor private func renderKeyed(_ context: _RenderContext) -> _RenderNode {
    // Deep in the render, the content is handed to the loop that drives the pass (see `_PendingRender`).
    if _RenderStaging.wantsDeferral { return deferRenderKeyed(context) }
    let node = renderer.render(context)
    applyBuilderKey(node)
    return node
  }

  /// A node standing in for `renderer.render(context)`, which the loop that drives the pass runs later.
  @inline(never) @MainActor private func deferRenderKeyed(_ context: _RenderContext) -> _RenderNode {
    let renderer = self.renderer
    let node = _RenderStaging.deferNode { renderer.render(context) }
    applyBuilderKey(node)
    return node
  }
}

/// Registers the owner of an erased view and returns its token. Out of line so the caller's frame, which stays on
/// the stack while the content renders, holds none of this bookkeeping.
@inline(never)
@MainActor private func _registerEmbeddedOwner(
  _ renderer: _AnyViewRenderer,
  key: _BuilderKey?,
  context: _RenderContext,
  registry: _RenderOwnerRegistry
) -> UInt64 {
  let ownerToken = _RenderOwnerTokenBox()
  let token = registry._register(context: context) { targetContext in
    var ownedTargetContext = targetContext
    ownedTargetContext._renderOwnerToken = ownerToken.value
    let node = renderer.render(ownedTargetContext)
    if let key { key.apply(to: node) }
    return node
  }
  ownerToken.value = token
  return token
}

/// Marks `node` as rendered by the owner `token` once its content has rendered.
@inline(never)
@MainActor private func _finishEmbeddedOwner(_ node: _RenderNode, token: UInt64, context: _RenderContext, registry: _RenderOwnerRegistry) {
  _postFinishOwner(node, token: token, path: context._fiberPath, registry: registry)
}

/// Marks `node` as rendered by the owner `token`: the owner above whatever owner returned the same node, and the
/// state scope at `path`. For a node that stands in for a render that has not run, when the render has.
@inline(never)
@MainActor func _postFinishOwner(_ node: _RenderNode, token: UInt64, path: _FiberPath, registry: _RenderOwnerRegistry) {
  if node._isPendingRender {
    node._keep(.owner(token: token, path: path, registry: registry))
  } else {
    _finishOwner(node, token: token, path: path, registry: registry)
  }
}

@MainActor func _finishOwner(_ node: _RenderNode, token: UInt64, path: _FiberPath, registry: _RenderOwnerRegistry) {
  if let inner = node._renderOwnerToken { registry._recordOuterOwner(inner, token) }
  node._renderOwnerToken = token
  _recordStateScopePath(node, path: path)
}

@MainActor func _recordStateScopePath(_ node: _RenderNode, path: _FiberPath) {
  if node._selfPending != nil { node._resolveSelf() }
  if node._sStateScopePaths.count < 16 {
    if !node._sStateScopePaths.contains(path) { node._sStateScopePaths.append(path) }
    return
  }
  var index = node._sStateScopePathIndex ?? Set(node._sStateScopePaths)
  node._sStateScopePathIndex = nil
  if index.insert(path).inserted { node._sStateScopePaths.append(path) }
  node._sStateScopePathIndex = index
}

/// An empty renderable value.
public nonisolated struct EmptyView: View {
  public typealias Body = Never
  public nonisolated init() {}
  public func _render(in context: _RenderContext) -> _RenderNode { .empty() }
}

/// A generic HTML primitive. It is useful for custom tags without adding a
/// framework type for every HTML element. An unsafe tag name renders as a
/// `div`; event-handler attributes and URL attributes with an unsafe scheme
/// are dropped.
package nonisolated struct HTMLElement: View {
  package typealias Body = Never
  package let tag: String
  package let attributes: [String: String]
  package let children: [AnyView]

  package init(tag: String, attributes: [String: String] = .init(), @ViewBuilder content: () -> some View = { EmptyView() }) {
    self.tag = tag
    self.attributes = attributes
    self.children = [AnyView(content())]
  }

  package init(tag: String, attributes: [String: String] = .init(), children: [AnyView]) {
    self.tag = tag
    self.attributes = attributes
    self.children = children
  }

  @MainActor package func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element(_isSafeElementName(tag) ? tag : "div")
    node.attributes = _safeAttributes(attributes)
    node.children = children.enumerated().flatMap { index, child in
      let rendered = child._render(in: context.child(_FiberKey(index)))
      return rendered.isEmpty ? [] : [rendered]
    }
    return node
  }
}

/// Values passed through the view environment.
public protocol EnvironmentKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

private func _defaultSwiftUIWebCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .current
  return calendar
}

/// What an environment entry holds, for `EquatableView`: a `Hashable` value is stamped with its hash, so a value
/// set again unchanged keeps its stamp from pass to pass; any other value gets a stamp no other write shares.
/// An environment object's stamp also holds the object: a memo that keeps the stamp keeps its address from being reused for
/// another object, which would then compare the same.
@_spi(Renderer) public struct _EnvironmentStamp: @unchecked Sendable {
  var hash: Int
  var unique: UInt64
  var object: AnyObject? = nil
  static let absent = _EnvironmentStamp(hash: 0, unique: 0)
}

extension _EnvironmentStamp: Equatable {
  public static func == (lhs: _EnvironmentStamp, rhs: _EnvironmentStamp) -> Bool {
    lhs.hash == rhs.hash && lhs.unique == rhs.unique && lhs.object === rhs.object
  }
}

/// What a deferred render of a view that compares its inputs turned into, kept until the pass settles
/// (`AnyView._renderReusing`).
final class _ReuseSnapshot {
  var node: _RenderNode?
}

/// Records the environment entries a render reads, with their stamps, so `EquatableView` can tell whether the
/// environment its content saw has changed. A read it cannot describe marks the render untracked.
@_spi(Renderer) public final class _EnvironmentReadRecorder {
  var reads: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)] = []
  var untracked = false
  /// The state, observation and leaf reads the render made (see `StateStore._recordedReads`).
  var stateReads = 0
  /// The environment the recorded render started from, when only what it read from there counts: a value a view sets
  /// for its own content (`.font` on a child, read by the text below) changes when the view's render does, so it is not
  /// a dependency of that render. Without it (`EquatableView`) every read counts.
  let base: EnvironmentValues?
  init(base: EnvironmentValues? = nil) { self.base = base }

  /// Records a read of an entry the render got from its environment, once: a render reads the same few entries over and
  /// over (every text its font), and an enclosing recorder takes all of them again.
  func record(_ key: ObjectIdentifier, _ stamp: _EnvironmentStamp) {
    if let base, base._stamp(for: key) != stamp { return }
    for read in reads where read.key == key { return }
    reads.append((key, stamp))
  }

  /// What a render inside this one read, as if this one had.
  func merge(_ inner: _EnvironmentReadRecorder) {
    for read in inner.reads { record(read.key, read.stamp) }
    if inner.untracked { untracked = true }
    stateReads &+= inner.stateReads
  }

  func merge(_ inner: [(key: ObjectIdentifier, stamp: _EnvironmentStamp)]) {
    for read in inner { record(read.key, read.stamp) }
  }
}

/// A render that hands something to an ancestor that gathers it during the pass (a toolbar item, a navigation title or
/// destination, a preference, a tab): reusing the render would leave it out, so the views around it render every time.
@_spi(Renderer) public func _renderRegistersWithAncestors() {
  EnvironmentValues._readRecorder?.untracked = true
}

public struct EnvironmentValues {
  // A single typed implementation is used on all targets. Built-in and custom
  // keys keep the same value semantics without Foundation or Any containers.
  private var storage = _TypedValueStorage<ObjectIdentifier>()
  private var objectStorage = _TypedValueStorage<ObjectIdentifier>()
  /// Environment-object stamps, under `_objectStampID`; key entries keep theirs in `storage`.
  private var objectStamps: [ObjectIdentifier: _EnvironmentStamp] = .init()
  /// Set while an `EquatableView` renders its content.
  nonisolated(unsafe) static var _readRecorder: _EnvironmentReadRecorder?
  /// Numbers come from the one counter the distinct-value table uses (`_newDistinctNumber`), so no two stamps share one.
  private static func uniqueStamp() -> _EnvironmentStamp {
    _EnvironmentStamp(hash: 0, unique: UInt64(_newDistinctNumber()))
  }
  @inline(__always) private func recordRead(_ id: ObjectIdentifier) {
    if let recorder = EnvironmentValues._readRecorder { recorder.record(id, _stamp(for: id)) }
  }
  func _stamp(for id: ObjectIdentifier) -> _EnvironmentStamp { storage.stamp(for: id) ?? objectStamps[id] ?? .absent }
  /// Monotonic value-storage revision used only by the renderer to distinguish
  /// an externally changed environment from an unchanged copy. A revision is
  /// intentionally not exposed through the SwiftUI-facing API.
  private var environmentRevision: UInt64 = 0
  /// Set only for a context produced by a SwiftUI `.environment` modifier.
  /// The bit is deliberately separate from `environmentRevision`: a local
  /// override and a root mutation can both be the first write (revision 1),
  /// but they must never be treated as the same inherited environment during
  /// a targeted refresh.
  private var localEnvironmentOverride = false
  // Internal selection sink used by generic TabView/Tag modifiers.  It keeps
  // enum-backed tab state typed without exposing an AnyHashable/router layer
  // through the public API.
  var tabSelectionSink: _TabSelectionSink? {
    get { EnvironmentValues._readRecorder?.untracked = true; return storedTabSelectionSink }
    set { storedTabSelectionSink = newValue }
  }
  private var storedTabSelectionSink: _TabSelectionSink? = nil
  /// Decides which `Tab` contents are built in the current TabView pass.
  var tabMount: _TabMountTracker? {
    get { EnvironmentValues._readRecorder?.untracked = true; return storedTabMount }
    set { storedTabMount = newValue }
  }
  private var storedTabMount: _TabMountTracker? = nil
  public init() {}

  public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value {
    get {
      let id = _storedTypeID(key)
      recordRead(id)
      if let value: K.Value = storage.value(for: id) { return value }
      return K.defaultValue
    }
    set {
      let id = _storedTypeID(key)
      storage.set(newValue, for: id, stamp: EnvironmentValues.uniqueStamp())
      _RuntimeMemoryMetrics.recordEnvironmentEntries(storage.count + objectStorage.count)
      _markEnvironmentMutation()
    }
  }

  /// The same entry for a `Hashable` value, which is stamped with its hash (see `_EnvironmentStamp`). Internal:
  /// the framework's own keys keep their stamp when set again unchanged; an application's keys take the
  /// unconstrained subscript and a fresh stamp per write, which only makes `EquatableView` re-render more often.
  package subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value where K.Value: Hashable {
    get {
      let id = _storedTypeID(key)
      recordRead(id)
      if let value: K.Value = storage.value(for: id) { return value }
      return K.defaultValue
    }
    set {
      let id = _storedTypeID(key)
      // The stamp names the value, not the write: an equal value keeps its number in any environment (so an
      // `EquatableView` can reuse its render), and two values that share a hash get different numbers.
      let stamp = _EnvironmentStamp(hash: newValue.hashValue, unique: UInt64(_memoDistinctIDNumber(newValue)))
      storage.set(newValue, for: id, stamp: stamp)
      _RuntimeMemoryMetrics.recordEnvironmentEntries(storage.count + objectStorage.count)
      _markEnvironmentMutation()
    }
  }

  @_spi(Renderer) public var _revision: UInt64 { environmentRevision }

  @_spi(Renderer) public var _hasLocalOverride: Bool { localEnvironmentOverride }

  @_spi(Renderer) public mutating func _markEnvironmentMutation() {
    environmentRevision &+= 1
  }

  @_spi(Renderer) public mutating func _markLocalEnvironmentOverride() {
    localEnvironmentOverride = true
  }
}

private enum FontEnvironmentKey: EnvironmentKey { static let defaultValue = Font.body }
private enum ForegroundEnvironmentKey: EnvironmentKey { static let defaultValue = Color.primary }
private enum EnabledEnvironmentKey: EnvironmentKey { static let defaultValue = true }
private enum ColorSchemeEnvironmentKey: EnvironmentKey {
  // The browser host updates ColorSchemeRuntime before mounting the root. A
  // computed default keeps an otherwise-unconfigured environment in sync with
  // the current system preference without changing the SwiftUI-facing API.
  static var defaultValue: ColorScheme { ColorSchemeRuntime.current }
}
private enum DismissEnvironmentKey: EnvironmentKey { static let defaultValue = DismissAction() }
private enum ButtonStyleEnvironmentKey: EnvironmentKey { static let defaultValue = ButtonStyleValue.automatic }
private enum ButtonStyleCustomEnvironmentKey: EnvironmentKey { static let defaultValue = false }
private enum ControlSizeEnvironmentKey: EnvironmentKey { static let defaultValue = ControlSize.regular }
private enum DefaultHoverEffectEnvironmentKey: EnvironmentKey { static let defaultValue = HoverEffect.automatic }
private enum HoverEffectEnabledEnvironmentKey: EnvironmentKey { static let defaultValue = true }
private enum HoverEffectGroupEnvironmentKey: EnvironmentKey { static let defaultValue: HoverEffectGroup? = nil }
private enum TintEnvironmentKey: EnvironmentKey { static let defaultValue: Color? = nil }
private enum RefreshEnvironmentKey: EnvironmentKey { static let defaultValue: RefreshAction? = nil }
private enum RedactionReasonsEnvironmentKey: EnvironmentKey { static let defaultValue = RedactionReasons() }
private enum PrivacySensitiveEnvironmentKey: EnvironmentKey { static let defaultValue = false }
private enum OpenURLEnvironmentKey: EnvironmentKey { static let defaultValue = OpenURLAction(unisolatedHandler: { _ in OpenURLAction.Result.systemAction }) }
private enum LocaleEnvironmentKey: EnvironmentKey { static let defaultValue = Locale(identifier: "en_US_POSIX") }
private enum CalendarEnvironmentKey: EnvironmentKey { static var defaultValue: Calendar { _defaultSwiftUIWebCalendar() } }
private enum TimeZoneEnvironmentKey: EnvironmentKey { static let defaultValue = TimeZone.current }
private enum ScenePhaseEnvironmentKey: EnvironmentKey { static let defaultValue = ScenePhase.active }
private enum AccessibilityReduceMotionEnvironmentKey: EnvironmentKey {
  static var defaultValue: Bool { AccessibilityRuntime.reduceMotion }
}
private enum AccessibilityReduceTransparencyEnvironmentKey: EnvironmentKey {
  static var defaultValue: Bool { AccessibilityRuntime.reduceTransparency }
}
private enum DynamicTypeSizeEnvironmentKey: EnvironmentKey {
  static let defaultValue = DynamicTypeSize.large
}
private enum FocusedEnvironmentKey: EnvironmentKey { static let defaultValue = false }
private enum DatePickerStyleEnvironmentKey: EnvironmentKey { static let defaultValue = "automatic" }
private enum TabViewStyleEnvironmentKey: EnvironmentKey { static let defaultValue = "automatic" }
private enum InSidebarEnvironmentKey: EnvironmentKey { static let defaultValue = false }
private enum TabViewCustomizationEnvironmentKey: EnvironmentKey { static let defaultValue = TabViewCustomization() }
// As SwiftUI, a TabView keeps every tab it has shown: going back to one shows its content at once, with its state.
// Hidden panels are `display: none`, so the browser skips their style and layout. `.tabViewMountPolicy(.recent(n))`
// rebuilds older tabs instead, for a tab view whose tabs are too large to keep.
private enum TabViewMountPolicyEnvironmentKey: EnvironmentKey { static let defaultValue = TabViewMountPolicy.keepVisited }
private enum TextFieldStyleEnvironmentKey: EnvironmentKey { static let defaultValue = "automatic" }
private enum PickerStyleEnvironmentKey: EnvironmentKey { static let defaultValue = "automatic" }
private enum LabelsHiddenEnvironmentKey: EnvironmentKey { static let defaultValue = false }
private enum ScrollContentBackgroundHiddenEnvironmentKey: EnvironmentKey { static let defaultValue = false }

/// Inherited control configuration written by `.textFieldStyle(_:)`,
/// `.pickerStyle(_:)`, `.labelsHidden()` and `.scrollContentBackground(_:)`.
/// Renderer SPI: controls in other framework modules (DatePicker) read it,
/// application code keeps using the SwiftUI modifiers.
extension EnvironmentValues {
  @_spi(Renderer) public var _textFieldStyle: String {
    get { self[TextFieldStyleEnvironmentKey.self] }
    set { self[TextFieldStyleEnvironmentKey.self] = newValue }
  }
  @_spi(Renderer) public var _pickerStyle: String {
    get { self[PickerStyleEnvironmentKey.self] }
    set { self[PickerStyleEnvironmentKey.self] = newValue }
  }
  @_spi(Renderer) public var _labelsHidden: Bool {
    get { self[LabelsHiddenEnvironmentKey.self] }
    set { self[LabelsHiddenEnvironmentKey.self] = newValue }
  }
  @_spi(Renderer) public var _scrollContentBackgroundHidden: Bool {
    get { self[ScrollContentBackgroundHiddenEnvironmentKey.self] }
    set { self[ScrollContentBackgroundHiddenEnvironmentKey.self] = newValue }
  }
}
package struct _ButtonStyleRenderer: Sendable {
  package let render: @MainActor (ButtonStyleConfiguration) -> AnyView
  package init(_ render: @escaping @MainActor (ButtonStyleConfiguration) -> AnyView) { self.render = render }
}
private enum ButtonStyleRendererEnvironmentKey: EnvironmentKey { static let defaultValue: _ButtonStyleRenderer? = nil }
private struct NavigationHistoryAdapterValue: @unchecked Sendable {
  let adapter: NavigationHistoryAdapter?
}
private enum NavigationHistoryEnvironmentKey: EnvironmentKey {
  static let defaultValue = NavigationHistoryAdapterValue(adapter: nil)
}
public extension EnvironmentValues {
  var font: Font {
    get {
      return self[FontEnvironmentKey.self]
    }
    set {
      self[FontEnvironmentKey.self] = newValue
    }
  }
  package var foregroundColor: Color {
    get {
      return self[ForegroundEnvironmentKey.self]
    }
    set {
      self[ForegroundEnvironmentKey.self] = newValue
    }
  }
  var isEnabled: Bool {
    get {
      return self[EnabledEnvironmentKey.self]
    }
    set {
      self[EnabledEnvironmentKey.self] = newValue
    }
  }

  var colorScheme: ColorScheme {
    get {
      return self[ColorSchemeEnvironmentKey.self]
    }
    set {
      self[ColorSchemeEnvironmentKey.self] = newValue
    }
  }

  var dismiss: DismissAction {
    get {
      return self[DismissEnvironmentKey.self]
    }
    set {
      self[DismissEnvironmentKey.self] = newValue
    }
  }

  /// The inherited button style is represented by a compact value token. A
  /// host stylesheet maps the token to concrete CSS. Apple exposes no
  /// environment key for this, so it stays package-only.
  package var buttonStyle: ButtonStyleValue {
    get {
      return self[ButtonStyleEnvironmentKey.self]
    }
    set {
      self[ButtonStyleEnvironmentKey.self] = newValue
    }
  }

  /// Whether the current button style supplies its own visual body. This is
  /// intentionally an internal environment detail; application code only
  /// sees SwiftUI's `ButtonStyle` protocol and `.buttonStyle(_:)` modifier.
  package var buttonStyleIsCustom: Bool {
    get {
      return self[ButtonStyleCustomEnvironmentKey.self]
    }
    set {
      self[ButtonStyleCustomEnvironmentKey.self] = newValue
    }
  }

  var controlSize: ControlSize {
    get {
      return self[ControlSizeEnvironmentKey.self]
    }
    set {
      self[ControlSizeEnvironmentKey.self] = newValue
    }
  }

  /// The hover effect inherited by eligible descendants that don't specify
  /// their own effect.
  package var defaultHoverEffect: HoverEffect {
    get { self[DefaultHoverEffectEnvironmentKey.self] }
    set { self[DefaultHoverEffectEnvironmentKey.self] = newValue }
  }

  /// Whether this subtree is allowed to display hover feedback.
  var isHoverEffectEnabled: Bool {
    get { self[HoverEffectEnabledEnvironmentKey.self] }
    set { self[HoverEffectEnabledEnvironmentKey.self] = newValue }
  }

  @_spi(Renderer) var _hoverEffectGroup: HoverEffectGroup? {
    get { self[HoverEffectGroupEnvironmentKey.self] }
    set { self[HoverEffectGroupEnvironmentKey.self] = newValue }
  }

  /// The calendar used by date-aware controls. This mirrors SwiftUI's
  /// environment value while keeping Foundation implementation out of WASI
  /// Core builds that do not use it.
  var calendar: Calendar {
    get { self[CalendarEnvironmentKey.self] }
    set { self[CalendarEnvironmentKey.self] = newValue }
  }

  /// The time zone used by date-aware controls.
  var timeZone: TimeZone {
    get { self[TimeZoneEnvironmentKey.self] }
    set { self[TimeZoneEnvironmentKey.self] = newValue }
  }

  /// The inherited date-picker style token. It is intentionally a semantic
  /// value so hosts can choose their native realization.
  package var datePickerStyle: String {
    get {
      return self[DatePickerStyleEnvironmentKey.self]
    }
    set {
      self[DatePickerStyleEnvironmentKey.self] = newValue
    }
  }

  package var tint: Color? {
    get {
      return self[TintEnvironmentKey.self]
    }
    set {
      self[TintEnvironmentKey.self] = newValue
    }
  }

  /// The active SwiftUI-style refresh action. It is optional outside a
  /// `.refreshable` subtree and lets child controls trigger the same action
  /// without knowing anything about the browser host.
  var refresh: RefreshAction? {
    get {
      return self[RefreshEnvironmentKey.self]
    }
    set {
      self[RefreshEnvironmentKey.self] = newValue
    }
  }

  /// Redaction reasons propagate through the environment just like SwiftUI.
  /// The renderer uses the value to apply a single semantic redaction surface
  /// while descendants can opt out with `.unredacted()`.
  /// Set by `privacySensitive()`: its text is redacted when `redactionReasons` holds `.privacy`.
  package var _isPrivacySensitive: Bool {
    get { self[PrivacySensitiveEnvironmentKey.self] }
    set { self[PrivacySensitiveEnvironmentKey.self] = newValue }
  }

  var redactionReasons: RedactionReasons {
    get {
      return self[RedactionReasonsEnvironmentKey.self]
    }
    set {
      self[RedactionReasonsEnvironmentKey.self] = newValue
    }
  }

  /// SwiftUI-compatible URL action. The default hands the URL to the system
  /// action, which the browser host performs (`_OpenURLSystem.open`); without a
  /// host, as in static/WASI rendering, it does nothing.
  @MainActor @preconcurrency var openURL: OpenURLAction {
    get {
      return self[OpenURLEnvironmentKey.self]
    }
    set {
      self[OpenURLEnvironmentKey.self] = newValue
    }
  }

  /// The locale inherited by formatting and localization-aware controls.
  var locale: Locale {
    get { self[LocaleEnvironmentKey.self] }
    set { self[LocaleEnvironmentKey.self] = newValue }
  }

  /// Mirrors SwiftUI's scene lifecycle value.  Browser hosts update this
  /// when the document becomes hidden/visible; other hosts default to active.
  var scenePhase: ScenePhase {
    get {
      return self[ScenePhaseEnvironmentKey.self]
    }
    set {
      self[ScenePhaseEnvironmentKey.self] = newValue
    }
  }

  /// Mirrors SwiftUI's accessibility motion preference. Browser hosts update
  /// the runtime value from `prefers-reduced-motion`; static and WASI hosts
  /// default to `false` unless an embedding environment supplies a value.
  var accessibilityReduceMotion: Bool {
    get {
      return self[AccessibilityReduceMotionEnvironmentKey.self]
    }
    set {
      self[AccessibilityReduceMotionEnvironmentKey.self] = newValue
    }
  }

  /// Mirrors SwiftUI's transparency reduction preference. It is kept as a
  /// normal environment value so app design-system modifiers can remain
  /// source-compatible while browser hosts decide how to realize materials.
  var accessibilityReduceTransparency: Bool {
    get {
      return self[AccessibilityReduceTransparencyEnvironmentKey.self]
    }
    set {
      self[AccessibilityReduceTransparencyEnvironmentKey.self] = newValue
    }
  }

  /// The current dynamic type category. Web hosts expose this value as a
  /// semantic token; applications can still use SwiftUI's familiar
  /// `.dynamicTypeSize(...)` modifier and `isAccessibilitySize` query.
  var dynamicTypeSize: DynamicTypeSize {
    get {
      return self[DynamicTypeSizeEnvironmentKey.self]
    }
    set {
      self[DynamicTypeSizeEnvironmentKey.self] = newValue
    }
  }

  /// Indicates whether the current control owns keyboard focus. The browser
  /// adapter can update this value while custom styles can read it through the
  /// same `@Environment(\.isFocused)` spelling used by SwiftUI.
  var isFocused: Bool {
    get {
      return self[FocusedEnvironmentKey.self]
    }
    set {
      self[FocusedEnvironmentKey.self] = newValue
    }
  }

  /// Internal type-keyed storage backing SwiftUI's modern
  /// `@Environment(Model.self)` and `.environment(model)` APIs.  It is kept
  /// separate from `EnvironmentKey` storage so key-path and model values can
  /// coexist without collisions.
  mutating func _setEnvironmentObject<ObjectType: AnyObject>(_ object: ObjectType) {
    objectStorage.set(object, for: _storedTypeID(ObjectType.self))
    // Objects are distinct entries from keys of the same type: the stamp lives under the object's own identifier.
    objectStamps[_objectStampID(ObjectType.self)] = _EnvironmentStamp(hash: ObjectIdentifier(object).hashValue, unique: 0, object: object)
    _RuntimeMemoryMetrics.recordEnvironmentEntries(storage.count + objectStorage.count)
    _markEnvironmentMutation()
  }

  /// The explicitly stored value for `key`, without falling back to its
  /// default. Used to tell an injected value from a missing one.
  func _storedValue<K: EnvironmentKey>(_ key: K.Type) -> K.Value? {
    recordRead(_storedTypeID(key))
    return storage.value(for: _storedTypeID(key))
  }

  func _environmentObject<ObjectType: AnyObject>(_ type: ObjectType.Type) -> ObjectType? {
    recordRead(_objectStampID(type))
    return objectStorage.value(for: _storedTypeID(type), as: type)
  }

  /// Reads an environment object named by its storage identifier and by its stamp identifier (`_objectStampID`). The read
  /// is recorded with the object's stamp, from the environment it was read from, so a render that read the object is
  /// remembered and renders again when another object takes its place (`recordRead`). Only a read whose stamp cannot be
  /// found marks the render untracked: nothing then proves what it read, so it is not remembered.
  func _environmentObjectByIdentifier<Value>(_ identifier: ObjectIdentifier, stamp: ObjectIdentifier, as type: Value.Type) -> Value? {
    // Counted as a state read, as before: `EquatableView` does not memoize a render that read an object.
    EnvironmentValues._readRecorder?.stateReads &+= 1
    guard let value = objectStorage.value(for: identifier, as: type) else { return nil }
    if _stamp(for: stamp) == .absent {
      EnvironmentValues._readRecorder?.untracked = true
    } else {
      recordRead(stamp)
    }
    return value
  }

  /// Internal type-erased style body hook. It is intentionally not exposed
  /// as a public web/runtime concept; the public API remains ButtonStyle.
  package var buttonStyleRenderer: _ButtonStyleRenderer? {
    get {
      return self[ButtonStyleRendererEnvironmentKey.self]
    }
    set {
      self[ButtonStyleRendererEnvironmentKey.self] = newValue
    }
  }

  /// Optional platform history bridge. Applications normally never set this;
  /// browser launchers install it while keeping URL/JavaScript details out of
  /// `NavigationStack` and View code.
  package var navigationHistory: NavigationHistoryAdapter? {
    get {
      return self[NavigationHistoryEnvironmentKey.self].adapter
    }
    set {
      self[NavigationHistoryEnvironmentKey.self] = NavigationHistoryAdapterValue(adapter: newValue)
    }
  }

  /// Internal value propagated by `.tabViewCustomization`. It is kept on the
  /// shared environment so a TabView can apply ordering/visibility while
  /// preserving the public SwiftUI spelling of the modifier.
  package var tabViewCustomization: TabViewCustomization {
    get {
      return self[TabViewCustomizationEnvironmentKey.self]
    }
    set {
      self[TabViewCustomizationEnvironmentKey.self] = newValue
    }
  }

  /// How long a `TabView` keeps the content of tabs the user has left.
  package var tabViewMountPolicy: TabViewMountPolicy {
    get { self[TabViewMountPolicyEnvironmentKey.self] }
    set { self[TabViewMountPolicyEnvironmentKey.self] = newValue }
  }

  /// Whether the view is in a `NavigationSplitView`'s sidebar column, where a list is a source list: a section's rows
  /// are rows of the list as its other rows are, not the cards of a grouped list.
  package var _isInSidebar: Bool {
    get { self[InSidebarEnvironmentKey.self] }
    set { self[InSidebarEnvironmentKey.self] = newValue }
  }

  /// The inherited `TabView` presentation token. The browser host owns the
  /// actual breakpoint behavior; application views only choose the semantic
  /// SwiftUI style.
  package var tabViewStyle: String {
    get {
      self[TabViewStyleEnvironmentKey.self]
    }
    set {
      self[TabViewStyleEnvironmentKey.self] = newValue
    }
  }
}

/// Host-neutral accessibility preferences used by environment defaults. A
/// browser adapter may install values from media queries; native/WASI hosts
/// can install their own platform preferences without changing View code.
package enum AccessibilityRuntime {
  private static let preferences = _Locked((reduceMotion: false, reduceTransparency: false))
  package static var reduceMotion: Bool {
    get { preferences.withLock { $0.reduceMotion } }
    set { preferences.withLock { $0.reduceMotion = newValue } }
  }
  package static var reduceTransparency: Bool {
    get { preferences.withLock { $0.reduceTransparency } }
    set { preferences.withLock { $0.reduceTransparency = newValue } }
  }

  package static func install(reduceMotion: Bool? = nil, reduceTransparency: Bool? = nil) {
    if let reduceMotion { self.reduceMotion = reduceMotion }
    if let reduceTransparency { self.reduceTransparency = reduceTransparency }
  }
}

/// SwiftUI-compatible dismiss action resolved by the active navigation or
/// presentation context during Fiber evaluation.
@MainActor @preconcurrency public struct DismissAction: Sendable {
  private let action: @MainActor () -> Void
  nonisolated package init(_ action: @escaping @MainActor () -> Void = {}) { self.action = action }
  @preconcurrency @MainActor public func callAsFunction() { action() }
}

/// SwiftUI scene lifecycle phases.  The enum intentionally has no platform
/// dependencies so the same application source compiles for native, WASI,
/// and browser hosts.
public enum ScenePhase: Comparable, Sendable {
  case active
  case inactive
  case background

  public static func < (lhs: ScenePhase, rhs: ScenePhase) -> Bool {
    let order: [ScenePhase: Int] = [.background: 0, .inactive: 1, .active: 2]
    return (order[lhs] ?? 0) < (order[rhs] ?? 0)
  }

  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .active: "active"
    case .inactive: "inactive"
    case .background: "background"
    }
  }
}

/// The result returned by a SwiftUI-style `OpenURLAction` invocation.
@MainActor @preconcurrency public struct OpenURLAction: Sendable {
  /// What a handler decided. As in SwiftUI, a struct of static members: `.handled`, `.discarded`, and the system's
  /// action, which opens the URL the action was called with, or the URL given to `systemAction(_:)`.
  public struct Result: Sendable {
    enum Kind: Sendable {
      case handled
      case discarded
      case systemAction(URL?)
    }
    let kind: Kind
    public static let handled = Result(kind: .handled)
    public static let discarded = Result(kind: .discarded)
    public static let systemAction = Result(kind: .systemAction(nil))
    public static func systemAction(_ url: URL) -> Result { Result(kind: .systemAction(url)) }
  }
  private let handler: @Sendable (URL) -> Result
  @MainActor @preconcurrency public init(handler: @escaping (URL) -> OpenURLAction.Result) {
    // SAFETY: SwiftUI hands the handler over from the main actor, where it is also called.
    nonisolated(unsafe) let handler = handler
    self.handler = { handler($0) }
  }
  // The environment default is built here: the public initializer is MainActor, as in SwiftUI.
  fileprivate nonisolated init(unisolatedHandler handler: @escaping @Sendable (URL) -> OpenURLAction.Result) { self.handler = handler }
  @preconcurrency @MainActor public func callAsFunction(_ url: URL) {
    switch handler(url).kind {
    case .handled, .discarded: return
    case .systemAction(let target): _OpenURLSystem.open(target ?? url)
    }
  }
}

/// The host's system action for a URL: a browser host opens it in a new window or tab. The browser runtime installs
/// it before the first render; without a host it does nothing.
@MainActor public enum _OpenURLSystem {
  public static var open: (URL) -> Void = { _ in }
}

@propertyWrapper public struct Environment<Value>: DynamicProperty {
  #if hasFeature(Embedded)
  private let embeddedGetter: ((EnvironmentValues) -> Value)?
  #else
  private let keyPath: KeyPath<EnvironmentValues, Value>?
  #endif
  private let objectType: ObjectIdentifier?
  /// The stamp an environment object is read by (`_objectStampID`), next to its storage identifier.
  private let objectStamp: ObjectIdentifier?
  /// Shared by every copy of the owning view value, exactly like SwiftUI's
  /// property storage: closures and tasks created from a body capture a copy
  /// of `self`, and must keep reading the environment that view was updated
  /// with after the render pass has finished.
  private let resolution = _EnvironmentResolution()

  #if hasFeature(Embedded)
  /// Compiler-input target used by the Embedded source-lowering pass.
  /// Application source still spells this as `@Environment(\.member)`.
  public init(_embedded getter: @escaping (EnvironmentValues) -> Value) {
    embeddedGetter = getter
    objectType = nil
    objectStamp = nil
  }
  #else
  public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
    nonisolated(unsafe) let keyPath = keyPath
    self.keyPath = keyPath
    objectType = nil
    objectStamp = nil
  }
  #endif

  public init(_ type: Value.Type) where Value: AnyObject {
    #if hasFeature(Embedded)
    embeddedGetter = nil
    #else
    keyPath = nil
    #endif
    objectType = _storedTypeID(type)
    objectStamp = _objectStampID(type)
  }

  public var wrappedValue: Value {
    let resolution = self.resolution
    let objectType = self.objectType
    let objectStamp = self.objectStamp
    #if hasFeature(Embedded)
    // SAFETY: the getter was handed over by the lowering pass and is only called on the main actor.
    nonisolated(unsafe) let embeddedGetter = self.embeddedGetter
    #else
    nonisolated(unsafe) let keyPath = self.keyPath
    #endif
    // Like SwiftUI's, the wrapper is nonisolated; the environment and render scope it reads are main-actor state.
    return _assumeMainActor {
      let inRender = StateRuntime.scope != nil
      if inRender { StateRuntime.scope?.store._recordEnvironmentRead() }
      #if hasFeature(Embedded)
      if let embeddedGetter {
        return resolution.first(inRender: inRender) { embeddedGetter($0) } ?? embeddedGetter(EnvironmentValues())
      }
      #else
      if let keyPath {
        return resolution.first(inRender: inRender) { $0[keyPath: keyPath] } ?? EnvironmentValues()[keyPath: keyPath]
      }
      #endif
      if let objectType, let objectStamp,
         let value = resolution.first(inRender: inRender, { $0._environmentObjectByIdentifier(objectType, stamp: objectStamp, as: Value.self) }) {
        #if !hasFeature(Embedded)
        if inRender { StateRuntime.scope?.store.observe(value as AnyObject) }
        #endif
        return value
      }
      return Self._missingEnvironmentObject()
    }
  }

  private static func _missingEnvironmentObject() -> Value {
    // Same failure as SwiftUI's "No Observable object of type X found". The
    // message names the type and the usual cause, because in Embedded builds
    // this trap surfaces in the browser as a bare `RuntimeError: unreachable`.
    fatalError("No environment object of type \(_swiftUIWebTypeName(Value.self)) supplied. Add .environment(_:) above the view or modifier that reads it; a modifier applied after .environment(_:) reads its parent's environment, not the one it wraps.")
  }
}

/// Reference storage behind `@Environment` and `@EnvironmentObject`.
///
/// SwiftUI resolves a view's environment when the view is updated and the
/// resolved value stays attached to that view value; it is not looked up from
/// a global when a task or action later reads the property. The render pass
/// records the environment it evaluated the view with here. Reads outside a
/// render pass (actions, `.task`, `Task {}` bodies, async view-model calls)
/// use that value first and then the environment of the event or task that is
/// running, so an async continuation never sees an unrelated environment.
@MainActor final class _EnvironmentResolution {
  /// The environment of the most recent render that read this property.
  private var resolved: EnvironmentValues?
  /// The environment active when the owning view value was created. A view
  /// created by its parent's body inherits that environment unless a
  /// modifier overrides it, so this is the last-resort value.
  private nonisolated(unsafe) let creation: EnvironmentValues?

  nonisolated init() {
    creation = StateRuntime.scope != nil ? EnvironmentRuntime.installed : nil
  }

  /// Reads a value from the most specific environment that provides it:
  /// the environment being rendered (recorded for later reads), then the
  /// last rendered one, the running event's, the running task's and finally
  /// the environment the view value was created in.
  func first<T>(inRender: Bool, _ read: (EnvironmentValues) -> T?) -> T? {
    if inRender, let installed = EnvironmentRuntime.installed {
      resolved = installed
      return read(installed)
    }
    if let resolved, let value = read(resolved) { return value }
    if let installed = EnvironmentRuntime.installed, let value = read(installed) { return value }
    if let task = EnvironmentRuntime.taskEnvironment, let value = read(task.values) { return value }
    if let creation, let value = read(creation) { return value }
    return nil
  }
}

/// A Sendable snapshot of an environment carried by a task-local value.
final class _EnvironmentSnapshot: @unchecked Sendable {
  let values: EnvironmentValues
  init(_ values: EnvironmentValues) { self.values = values }
}

package enum EnvironmentRuntime {
  /// The environment installed by the render pass or event currently running
  /// on this thread, or `nil` outside of both.
  static var installed: EnvironmentValues? {
    get { _RenderThreadState.current.environment }
    set { _RenderThreadState.current.environment = newValue }
  }

  /// The environment of the task started by a view (`.task`) or created while
  /// one of its actions ran (`Task {}` inside a Button action). Task-local
  /// values are inherited by child and unstructured tasks, so async work keeps
  /// the environment of the view that started it across suspension points.
  static let taskEnvironmentValue = TaskLocal<_EnvironmentSnapshot?>(wrappedValue: nil)
  static var taskEnvironment: _EnvironmentSnapshot? { taskEnvironmentValue.get() }

  static package var current: EnvironmentValues {
    get { installed ?? taskEnvironment?.values ?? EnvironmentValues() }
    set { installed = newValue }
  }

  /// Runs a synchronous action with `environment` installed for synchronous
  /// reads and inherited by tasks the action creates.
  static func perform<Result>(with environment: EnvironmentValues?, _ action: () -> Result) -> Result {
    guard let environment else { return action() }
    let previous = installed
    installed = environment
    defer { installed = previous }
    return taskEnvironmentValue.withValue(_EnvironmentSnapshot(environment)) { action() }
  }
}

/// Rendering-time context. Context values are immutable snapshots, making
/// rendering deterministic and straightforward to test.
@MainActor public struct _RenderContext {
  public var environment: EnvironmentValues
  /// The identity path, as a chain that shares its prefix (appending a key costs the same at any depth).
  @_spi(Renderer) public var _fiberPath: _FiberPath
  /// The identity path as a list of keys, from the root. Linear in the depth: renderer code uses `_fiberPath`.
  public var path: [_FiberKey] {
    get { _fiberPath.keys }
    set { _fiberPath = _FiberPath(newValue) }
  }
  package var stateStore: StateStore
  /// A short stable name for this view's identity path, for DOM ids and attributes (`root` for the root). The path text
  /// is as long as the depth; this is not (see `_FiberPath._compactID`).
  @_spi(Renderer) public var _compactPathID: String { _fiberPath._compactID(in: stateStore._compactPathIDs) }
  public var preferenceStore: _PreferenceStore
  // Navigation context is runtime state injected by NavigationStack. It is
  // deliberately internal so application code only sees SwiftUI-shaped APIs.
  var navigationContext: NavigationContext?
  // Modifiers attached outside NavigationStack are collected here and adopted
  // by the stack when it creates its runtime context.
  var navigationSetup: _NavigationSetup?
  // Browser-only lazy collection scope. This is an internal copy-on-child
  // value; keeping it in Core lets ordinary view builders participate without
  // adding a Web/DOM concept to the public API.
  @_spi(Renderer) public var lazyAxis: _LazyAxis?
  @_spi(Renderer) public var lazyCollectionsEnabled: Bool
  /// Explicit lazy containers (LazyV/HStack and Lazy*Grid) defer their
  /// collection bodies even when the current collection is short. List/Table
  /// may still use the renderer's small-collection eager fast path.
  @_spi(Renderer) public var lazyCollectionsForceDeferred: Bool
  @_spi(Renderer) public var lazyLaneCount: Int?
  /// Internal owner metadata used by FiberTree.  These fields are renderer
  /// SPI so Core remains free of DOM/JavaScript concepts in its public API.
  @_spi(Renderer) public var _renderOwnerRegistry: _RenderOwnerRegistry?
  @_spi(Renderer) public var _renderOwnerToken: UInt64?
  /// A dry run used to learn what a view would look like in another state
  /// (hover styling). It registers no owners and runs no effects.
  @_spi(Renderer) public var _speculative = false
  /// The proposal flowing from a layout boundary. It is renderer metadata;
  /// user layouts receive the public `ProposedViewSize` value instead.
  @_spi(Renderer) public var _layoutProposal: ProposedViewSize?
  /// The transaction of this subtree when a `.transaction` or `.animation(_:value:)` above it changed it; nil means
  /// the commit's own (`StateStore._commitTransaction`).
  package var _transactionOverride: Transaction? = nil
  /// Set under `transaction(_:body:)`: the override the placeholder (the view the closure modifies) is rendered with, since
  /// the changed transaction is for the closure's modifiers only.
  package var _placeholderTransaction: _PlaceholderTransaction? = nil
  /// Set when a transaction modifier above cleared an animation it inherited (`.transaction { $0.animation = nil }`, or
  /// `.animation(nil, value:)`): the page is told, since it would otherwise play the ancestor's armed timing here.
  package var _animationCleared = false
  /// The render owner of the nearest `overlayPreferenceValue` or `backgroundPreferenceValue` above: a view below that gives
  /// it an anchor renders it again when the anchor's frame changes, since the layer is drawn from the anchor.
  package var _preferenceLayerOwner: UInt64? = nil
  /// How many modifiers are stacked above this point on the view at this path. Modifiers of one view share its path, so
  /// the state a modifier keeps by path (the history of a value-scoped animation or transaction, the data of an
  /// animatable modifier) is keyed with it too: two of them on one view each keep their own.
  package var _modifierDepth = 0
  /// The key of the state a modifier keeps for the view at this path (`suffix` names the kind of state).
  package func _modifierStateKey(_ suffix: String) -> String {
    _modifierDepth == 0 ? _compactPathID + suffix : _compactPathID + suffix + "." + String(_modifierDepth)
  }
  /// Whether a run of frame, padding and fixedSize modifiers may share one element here (`_SemanticLayers`). It cannot
  /// below a container whose content the browser lays out with CSS instead of the layout host (the panes of a split view),
  /// where the CSS of each wrapper element is the layout.
  @_spi(Renderer) public var _mergesLayoutLayers = true
  /// Shared renderer-owned cache storage for `Layout` values. This is kept in
  /// the context so nested layouts naturally use the same lifetime as their
  /// containing Fiber tree while remaining invisible to SwiftUI-facing code.
  @_spi(Renderer) public var _layoutCacheStore: _LayoutCacheStore?
  /// Persistent values for browser-backed split dividers. The store is keyed
  /// by the semantic render path, so changing a parent's content does not
  /// reset a nested split view's divider positions.
  @_spi(Renderer) public var _splitViewStateStore: _SplitViewStateStore?
  /// Set while an overlay renders its content: the solid strokes painted there are recorded, so the overlay can
  /// paint a stroke that is its whole content on its base instead (see `OverlayModifier`).
  var _strokeOverlayProbe: _StrokeOverlayProbe?

  package init(environment: EnvironmentValues = .init(), path: [_FiberKey] = [], stateStore: StateStore = StateStore(), preferenceStore: _PreferenceStore = _PreferenceStore()) {
    self.init(environment: environment, path: path, stateStore: stateStore, preferenceStore: preferenceStore, _layoutCacheStore: nil, _splitViewStateStore: nil)
  }

  package init(environment: EnvironmentValues = .init(), path: [_FiberKey] = [], stateStore: StateStore = StateStore(), preferenceStore: _PreferenceStore = _PreferenceStore(), _layoutCacheStore: _LayoutCacheStore?, _splitViewStateStore: _SplitViewStateStore? = nil) {
    self.environment = environment
    self._fiberPath = _FiberPath(path)
    self.stateStore = stateStore
    self.preferenceStore = preferenceStore
    self.navigationContext = nil
    self.navigationSetup = nil
    self.lazyAxis = nil
    self.lazyCollectionsEnabled = false
    self.lazyCollectionsForceDeferred = false
    self.lazyLaneCount = nil
    self._renderOwnerRegistry = nil
    self._renderOwnerToken = nil
    self._layoutProposal = nil
    self._layoutCacheStore = _layoutCacheStore ?? _LayoutCacheStore()
    self._splitViewStateStore = _splitViewStateStore ?? _SplitViewStateStore()
  }

  public func child(_ key: _FiberKey? = nil) -> _RenderContext {
    var next = self
    if let key { next._fiberPath.append(key); next._modifierDepth = 0 }
    return next
  }

  /// Whether a container that lays its content out itself ends the enclosing lazy scope. A collection in a ScrollView,
  /// a ZStack or a stack across the lazy axis is not a run of the lazy stack's rows: windowing it along that axis would
  /// size its spacers on the wrong axis (a horizontal shelf of chips in a LazyVStack measured by height). `axis` is
  /// the one the container shares with the scope, which then goes on (a VStack in a LazyVStack).
  package func _endsLazyScope(keeping axis: _LazyAxis? = nil) -> Bool {
    lazyAxis != nil && lazyAxis != axis
  }
}

/// Renders `view` in `context` without its lazy scope (see `_RenderContext._endsLazyScope`). Out of line, so the
/// container keeps no second context in its frame on the common path, where there is no scope to end.
@inline(never)
@MainActor func _renderEndingLazyScope<V: View>(_ view: V, in context: _RenderContext) -> _RenderNode {
  var inner = context
  inner.lazyAxis = nil
  inner.lazyCollectionsForceDeferred = false
  inner.lazyLaneCount = nil
  return view._render(in: inner)
}

/// The environment-change modifier. Modifiers and the Embedded lowering of `.environment(\.key, value)`
/// build it; it is not a SwiftUI declaration, so it is reachable only through the `Renderer` SPI.
@_spi(Renderer) public nonisolated struct EnvironmentOverride: ViewModifier {
  let apply: (inout EnvironmentValues) -> Void
  /// The color scheme this override sets, if it sets one. Its subtree is marked with it, as `.preferredColorScheme`
  /// marks one, so the subtree's CSS `color-scheme` and the semantic colors inside it follow that scheme.
  let colorScheme: ColorScheme?
  @_spi(Renderer) public init(apply: @escaping (inout EnvironmentValues) -> Void, colorScheme: ColorScheme? = nil) {
    self.apply = apply
    self.colorScheme = colorScheme
  }
  /// `.environment(\.colorScheme, scheme)` as the Embedded lowering spells it.
  @_spi(Renderer) public init(colorScheme: ColorScheme) {
    self.init(apply: { $0.colorScheme = colorScheme }, colorScheme: colorScheme)
  }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    apply(&context.environment)
    context.environment._markLocalEnvironmentOverride()
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    apply(&context.environment)
    context.environment._markLocalEnvironmentOverride()
    // The scheme holds for this subtree only. `preferredColorScheme` also writes `data-color-scheme`, and the host lifts
    // that one to the document; the scope attribute tells the two apart.
    if let colorScheme { _applyScopedColorScheme(colorScheme, to: node) }
  }
}

/// Marks the roots a subtree publishes with its scheme. A fragment is not published as an element (a multi-child one is
/// flattened into its children), so the scheme goes onto each of its children, and a root that already carries a scoped scheme
/// keeps it: the modifier closest to the content is applied first, and the more local override wins.
@MainActor private func _applyScopedColorScheme(_ scheme: ColorScheme, to node: _RenderNode) {
  if node.kind == .fragment {
    for child in node.children { _applyScopedColorScheme(scheme, to: child) }
    return
  }
  guard node.attributes["data-color-scheme-scope"] == nil else { return }
  node.attributes["data-color-scheme"] = scheme.rawValue
  node.attributes["data-color-scheme-scope"] = "subtree"
}

/// Internal preference writer/reader modifiers.  They intentionally do not
/// wrap the rendered node, keeping Fiber identity and DOM event ownership on
/// the original view while values flow through the shared render context.
package nonisolated struct PreferenceWritingModifier<Key: PreferenceKey>: ViewModifier {
  package let value: Key.Value
  package init(value: Key.Value) { self.value = value }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    _renderRegistersWithAncestors()
    context.preferenceStore.write(value, for: Key.self)
  }
}

package nonisolated struct PreferenceActionModifier<Key: PreferenceKey>: ViewModifier where Key.Value: Equatable {
  package let action: @MainActor (Key.Value) -> Void
  package init(action: @escaping @MainActor (Key.Value) -> Void) { self.action = action }
  @MainActor package func _modifyContext(_ context: inout _RenderContext) { _notePreferenceReader(Key.self, in: &context) }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let store = context.preferenceStore
    let action = self.action
    // The reader sees the writes that come before it, whenever it runs (see `_RenderStaging.ordered`).
    _RenderStaging.ordered { limit in
      if let limit {
        if store.changed(for: Key.self, before: limit) { action(store.value(for: Key.self, before: limit)) }
      } else if store.changed(for: Key.self) {
        action(store.value(for: Key.self))
      }
    }
  }
}

extension _RenderNode {
  /// Gives the node a builder key like `_BuilderKey.apply`, now or when the render this node stands in for has run.
  @inline(__always) func _postKey(_ key: _FiberKey, overriding: Bool) {
    if _selfPending != nil { _keep(.key(key, overriding: overriding)) } else if overriding || self.key == nil { self.key = key }
  }
}

/// Runs an erased view's body renderer, or hands it to the loop that drives the pass when the render is deep. The
/// native renderer forms bodies under Observation tracking and runs this part outside it, so it can wait.
@inline(__always)
@MainActor func _renderBody(_ renderer: @escaping @MainActor (_RenderContext) -> _RenderNode, _ context: _RenderContext) -> _RenderNode {
  if _RenderStaging.wantsDeferral { return _deferRenderBody(renderer, context) }
  return renderer(context)
}

@inline(never)
@MainActor private func _deferRenderBody(_ renderer: @escaping @MainActor (_RenderContext) -> _RenderNode, _ context: _RenderContext) -> _RenderNode {
  _RenderStaging.deferNode { renderer(context) }
}
