@_spi(Renderer) import SwiftUIWebCore

#if canImport(Observation) && !hasFeature(Embedded)
#endif

/// Resolves dirty lowered-Observation routes without letting readers of one
/// property hide a missing route for another property. Each dirty source must
/// retain at least one live owner; stale siblings within a source are pruned.
func _activePublishedObservationOwners(
  bySource groups: [UInt64: Set<UInt64>],
  resolve: (UInt64) -> UInt64?
) -> Set<UInt64>? {
  var activeOwners = Set<UInt64>()
  for candidates in groups.values {
    // A changed source nothing has read yet needs no owner: there is nothing
    // to invalidate. Readers that exist but cannot be resolved still force
    // the conservative root pass below.
    if candidates.isEmpty { continue }
    var sourceHasActiveOwner = false
    for candidate in candidates {
      guard let activeOwner = resolve(candidate) else { continue }
      activeOwners.insert(activeOwner)
      sourceHasActiveOwner = true
    }
    guard sourceHasActiveOwner else { return nil }
  }
  return activeOwners
}

enum _PublishedObservationRouteResolution: Equatable {
  case groupsUnavailable
  case sourceCountMismatch
  case groupsWithoutActiveOwners(unresolvedOwnerTokens: Int)
  case routed(owners: Set<UInt64>, unresolvedOwnerTokens: Int)
}

func _resolvePublishedObservationOwners(
  sourceCount: Int,
  groups: [UInt64: Set<UInt64>]?,
  resolve: (UInt64) -> UInt64?
) -> _PublishedObservationRouteResolution {
  guard let groups else { return .groupsUnavailable }
  guard sourceCount == groups.count else { return .sourceCountMismatch }
  var unresolvedOwnerTokens = 0
  guard let owners = _activePublishedObservationOwners(bySource: groups, resolve: { token in
    guard let owner = resolve(token) else {
      unresolvedOwnerTokens += 1
      return nil
    }
    return owner
  }) else {
    return .groupsWithoutActiveOwners(unresolvedOwnerTokens: unresolvedOwnerTokens)
  }
  return .routed(owners: owners, unresolvedOwnerTokens: unresolvedOwnerTokens)
}

/// Finds the nearest mounted render-owner boundary for a retained structural
/// path. The root is deliberately excluded: if no narrower boundary survives,
/// callers keep the conservative full-root invalidation path.
func _nearestMountedRenderOwnerIdentity(
  path ownerPath: [_FiberKey],
  rootKey: _FiberKey = _FiberKey("root"),
  isMountedRenderOwner: (FiberIdentity) -> Bool
) -> FiberIdentity? {
  var path = _FiberPath()
  path.append(rootKey)
  for key in ownerPath { path.append(key) }
  while path.count > 1 {
    let candidate = FiberIdentity(fiberPath: path)
    if isMountedRenderOwner(candidate) { return candidate }
    path = path.parent
  }
  return nil
}

/// A fiber's identity: the keys from the root, as a chain that shares its prefix with the identity of the parent. It is
/// the same type as `_FiberPath`, not a wrapper of it: Embedded Swift emits its own copy of the `Dictionary`/`Set`
/// code for every key type, and the tables keyed by an identity and by a path then share one.
package typealias FiberIdentity = _FiberPath

extension _FiberPath {
  package init(fiberPath: _FiberPath) { self = fiberPath }
  package init(path: [_FiberKey]) { self.init(path) }
  package var fiberPath: _FiberPath { self }
  /// The keys from the root. Linear in the depth.
  package var path: [_FiberKey] { keys }
  /// The identity of the child under `key`.
  package func child(_ key: _FiberKey) -> _FiberPath { appending(key) }
}

/// Compact structural identity used by the retained graph. The semantic
/// `FiberIdentity` path remains available for event routing and compatibility;
/// this generational handle is the renderer's fast arena key and prevents a
/// stale callback from targeting a recycled node. It is SPI-only so normal
/// SwiftUI application code cannot depend on renderer identity.
@_spi(Renderer) public struct StructuralNodeID: Hashable, Sendable {
  public let index: UInt32
  public let generation: UInt32
  public init(index: UInt32, generation: UInt32) {
    self.index = index; self.generation = generation
  }

  /// The id as one integer, the generation above the index. Tables keyed by an id use it: Embedded Swift emits its own
  /// copy of the `Dictionary`/`Set` code for every key type, and `UInt64` keys share the copy the owner tables use.
  package var packed: UInt64 { UInt64(generation) << 32 | UInt64(index) }
  package init(packed: UInt64) {
    index = UInt32(truncatingIfNeeded: packed)
    generation = UInt32(truncatingIfNeeded: packed >> 32)
  }
}

/// One coalesced value update emitted by the internal binding scheduler. It is
/// public only because the browser adapter is a separate SwiftPM target; the
/// underscore keeps it out of the normal application API.
package struct _LeafUpdate {
  package let fiberIdentity: FiberIdentity
  package let structuralID: StructuralNodeID
  package let operation: _LeafBindingOperation
  package let value: String
  package init(fiberIdentity: FiberIdentity, structuralID: StructuralNodeID, operation: _LeafBindingOperation, value: String) {
    self.fiberIdentity = fiberIdentity; self.structuralID = structuralID; self.operation = operation; self.value = value
  }
}

/// Browser-facing description of a lazy collection in the retained graph.
/// `containerIdentity` is the nearest element Fiber, while `ownerIdentity`
/// remains the logical ForEach owner whose children carry SwiftUI identity.
package struct _LazyCollectionInfo {
  package let ownerIdentity: FiberIdentity
  package let containerIdentity: FiberIdentity
  package let descriptor: _LazyCollectionDescriptor

  package init(ownerIdentity: FiberIdentity, containerIdentity: FiberIdentity, descriptor: _LazyCollectionDescriptor) {
    self.ownerIdentity = ownerIdentity
    self.containerIdentity = containerIdentity
    self.descriptor = descriptor
  }
}

@_spi(Renderer) public struct _FiberRuntimeMetrics: Sendable {
  public fileprivate(set) var bodyEvaluations = 0
  /// Approximate number of _RenderNode values produced by body evaluation.
  /// _RenderNode is reference-backed today, so this is deliberately named as a
  /// logical allocation count rather than pretending to be an allocator trace.
  public fileprivate(set) var renderNodeAllocations = 0
  public fileprivate(set) var structuralNodeVisits = 0
  public fileprivate(set) var structuralNodeAllocations = 0
  public fileprivate(set) var reconciliationOperations = 0
  /// Number of logical owners/subtrees selected by the invalidation
  /// classifier. This is distinct from reconciliation operations because a
  /// targeted subtree may reconcile to an identical representation.
  public fileprivate(set) var invalidatedOwners = 0
  /// Logical invalidation targets selected before reconciliation. A root pass
  /// contributes one target; an owner pass contributes one per disjoint owner.
  /// Actual retained-node work remains available through
  /// `structuralNodeVisits`/`reconciledNodes` without an extra hot-path walk.
  public fileprivate(set) var invalidatedNodes = 0
  /// Number of nodes entering `reconcile`. Kept separate from structural
  /// visits for hosts that instrument/short-circuit a visit in the future.
  public fileprivate(set) var reconciledNodes = 0
  public fileprivate(set) var bindingCellUpdates = 0
  public fileprivate(set) var staleGenerationSkips = 0
  public fileprivate(set) var schedulerInvalidations = 0
  public fileprivate(set) var schedulerLeafFlushes = 0
  public fileprivate(set) var schedulerStructuralFlushes = 0
  public fileprivate(set) var schedulerSubtreeFlushes = 0
  public fileprivate(set) var subtreeOwnerInvalidations = 0
  /// Total identity depth and rendered nodes for selected owner targets.
  /// These quantify whether a targeted update stayed at the leaf boundary.
  public fileprivate(set) var subtreeTargetPathDepthTotal = 0
  public fileprivate(set) var subtreeTargetRenderNodeCount = 0
  public fileprivate(set) var staleSubtreeRendererFallbacks = 0
  public fileprivate(set) var staleSubtreeOwnerTokens = 0
  /// Targeted passes that fell back to the root because an owner's node came back under another key in its parent.
  public fileprivate(set) var rekeyedOwnerRootFallbacks = 0
  /// Owner-router evidence for Embedded browser workload diagnostics.
  public fileprivate(set) var publishedObservationTargets = 0
  public fileprivate(set) var publishedObservationRouteMisses = 0
  public fileprivate(set) var publishedObservationGroupsUnavailable = 0
  public fileprivate(set) var publishedObservationSourceCountMismatches = 0
  public fileprivate(set) var publishedObservationGroupsWithoutActiveOwners = 0
  public fileprivate(set) var publishedObservationUnresolvedOwnerTokens = 0
  /// Why a lowered observation owner could not be routed to a live Fiber.
  /// Missing paths may indicate retired-path history pressure; an unmounted
  /// path is a distinct stale-owner case and keeps the conservative root path.
  public fileprivate(set) var publishedObservationOwnerPathsUnavailable = 0
  public fileprivate(set) var publishedObservationOwnerPathsNotMounted = 0
  public fileprivate(set) var publishedObservationOwnerPathRemaps = 0
  public fileprivate(set) var stateOwnerRouteMisses = 0
  public fileprivate(set) var deferredRootPasses = 0
  public fileprivate(set) var deferredHiddenOwnerRenders = 0
  public fileprivate(set) var leafRootPasses = 0
  public fileprivate(set) var observationRootPasses = 0
  public fileprivate(set) var externalRootPasses = 0
  public fileprivate(set) var nestedChangeRootFallbacks = 0
  public fileprivate(set) var ownerRouteRootFallbacks = 0
  public fileprivate(set) var domOperations = 0
  /// Number of Swift/WASM-to-browser command-buffer submissions. A normal
  /// structural or leaf commit contributes at most one; a missing helper or
  /// compatibility-only host records a fallback call instead.
  public fileprivate(set) var bridgeBatches = 0
  public fileprivate(set) var bridgeCommands = 0
  public fileprivate(set) var bridgeFallbackCalls = 0
  public fileprivate(set) var bridgeIndexRebuilds = 0
  public fileprivate(set) var retainedStructuralNodes = 0
  public fileprivate(set) var lazyMaterializations = 0
  public fileprivate(set) var lazyLogicalRowsMaterialized = 0
  /// Number of semantically static subtree candidates discovered while
  /// rendering. A candidate has no events, tasks, leaf bindings or deferred
  /// lazy descriptor and all descendants satisfy the same rule.
  public fileprivate(set) var staticTemplateCandidates = 0
  /// Hits in the bounded semantic-template fingerprint cache. The cache is a
  /// compact description cache, not a shared mutable _RenderNode pool.
  public fileprivate(set) var staticTemplateHits = 0
  public fileprivate(set) var staticTemplateMisses = 0
  /// Number of retained _RenderNode representations reused by reconciliation.
  /// Reuse also skips the subtree walk and therefore avoids DOM mutations when
  /// the complete semantic template is unchanged.
  public fileprivate(set) var staticTemplateReuses = 0
  /// Subtrees an `EquatableView` handed back unchanged, which reconciliation did not walk.
  public fileprivate(set) var equatableSubtreesReused = 0
  /// Number of compact semantic mutation records emitted by the reconciler.
  public fileprivate(set) var packedMutationRecords = 0
  /// Six-word record storage plus side-table words prepared for the browser
  /// commit boundary. This is a logical byte count, not an allocator trace.
  public fileprivate(set) var packedMutationBytes = 0
  /// Number of compatibility materializations into the historical `Mutation`
  /// enum. Browser hosts use the packed buffer directly on their hot path.
  public fileprivate(set) var packedMutationMaterializations = 0
  /// Number of commits that reused the retained packed buffer capacity.
  public fileprivate(set) var packedMutationBufferReuses = 0
  /// Retained representation census. The Fiber and _RenderNode counts are
  /// intentionally reported separately because the graphs share semantic
  /// objects only through references; their child arrays are distinct storage.
  public fileprivate(set) var retainedFiberNodes = 0
  public fileprivate(set) var retainedRenderNodeNodes = 0
  public fileprivate(set) var retainedFiberChildEdges = 0
  public fileprivate(set) var retainedRenderNodeChildEdges = 0
  /// Semantic reconciliation counters used by identity diagnostics.
  public fileprivate(set) var createdNodes = 0
  public fileprivate(set) var removedNodes = 0
  public fileprivate(set) var retainedNodes = 0
  public fileprivate(set) var relaidOutNodes = 0
}

/// Sizes of one tree's structural arena and dependency graph, for lifecycle tests and health checks.
@_spi(Renderer) public struct _RuntimeDiagnostics: Sendable, Equatable {
  public let liveNodes: UInt64
  public let retainedSlots: UInt64
  public let dependencyEdges: UInt64

  public init(liveNodes: UInt64, retainedSlots: UInt64, dependencyEdges: UInt64) {
    self.liveNodes = liveNodes
    self.retainedSlots = retainedSlots
    self.dependencyEdges = dependencyEdges
  }
}

/// Host-visible observation state for one retained tree. This is intentionally
/// a value snapshot: callbacks and model references never cross the renderer
/// diagnostics boundary.
@_spi(Renderer) public struct _FiberObservationDiagnostics: Sendable, Equatable {
  public let stateStore: _StateStoreObservationDiagnostics
  /// All owner tokens coalesced for the pending turn, before ancestor
  /// subsumption. This is useful when diagnosing why a write fan-out grew.
  public let candidateSubtreeOwners: [UInt64]
  /// The minimum safe retained subtree set after removing descendants of an
  /// already-selected ancestor.
  public let pendingSubtreeOwners: [UInt64]
  public let rootFallbackPending: Bool
  public let disposed: Bool

  public init(
    stateStore: _StateStoreObservationDiagnostics,
    candidateSubtreeOwners: [UInt64] = [],
    pendingSubtreeOwners: [UInt64] = [],
    rootFallbackPending: Bool = false,
    disposed: Bool = false
  ) {
    self.stateStore = stateStore
    self.candidateSubtreeOwners = candidateSubtreeOwners
    self.pendingSubtreeOwners = pendingSubtreeOwners
    self.rootFallbackPending = rootFallbackPending
    self.disposed = disposed
  }

  public var plan: _InvalidationPlan {
    if rootFallbackPending { return .root }
    if !pendingSubtreeOwners.isEmpty { return .subtree(pendingSubtreeOwners) }
    return stateStore.plan
  }
}

@MainActor
package final class Fiber {
  package let identity: FiberIdentity
  package let structuralID: StructuralNodeID
  package private(set) var viewType: String
  package private(set) var renderNode: _RenderNode
  /// Erased-view owner token used for targeted subtree reevaluation.
  package private(set) var renderOwnerToken: UInt64?
  package var node: _RenderNode { renderNode }
  /// Parent identity is stored instead of a weak/unowned object reference.
  /// Embedded Swift intentionally omits weak/unowned runtime support; the
  /// tree owns Fibers and identity is sufficient to navigate or index parents.
  package private(set) var parentIdentity: FiberIdentity?
  package var children: [Fiber]
  package let stateStore: StateStore
  /// The rows this lazy owner last materialized, with the collection revision and count they were rendered from and
  /// the keys of the rows.
  package var _lazyWindow: (revision: UInt64, lower: Int, upper: Int, count: Int, before: Double, keys: [_FiberKey])?

  /// Epoch of the last change to this fiber or anything below it. A browser
  /// host that publishes the tree compares it with the last epoch the DOM
  /// acknowledged to reuse whole subtrees instead of serializing them again.
  package internal(set) var version: UInt64
  /// True when this subtree carries side effects that are recomputed at every
  /// publish (lazy windows, secure fields, mounted host views), so it can
  /// never be treated as unchanged.
  package internal(set) var isVolatile = false
  /// Filled by the publisher: the epoch of the last publication that carried this fiber's element.
  package var publishedEpoch: UInt64 = 0
  /// Filled by the publisher: a hash of the element alone (its tag and attributes, a text leaf's text; 0 when it has
  /// none) as last published, and the epoch of the first publication since which every publication that carried the
  /// element gave it that hash (0 when unknown). A host that acknowledged that epoch or a later one holds the element with
  /// these attributes, so they need not be sent again.
  package var publishedOwnHash: UInt64 = 0
  package var ownHashSince: UInt64 = 0
  /// Filled by the binary publisher (Documentation/Architecture/BINARY_PATCHES.md, "Swift side"): what the host holds of
  /// this fiber's element. `firstPublishedEpoch` is the first publication that carried the element under its current
  /// identity (`publishedIDHash`: its `data-embedded-node-id`, tag and namespace), 0 when the host does not hold it. A host
  /// that acknowledged that epoch or a later one holds the element. `publishedOwnHash` / `ownHashSince` say the same of its
  /// attributes and `publishedChildrenHash` / `childrenHashSince` of its list of children (the ids of its children in the
  /// DOM, or the text of a text-only parent).
  package var firstPublishedEpoch: UInt64 = 0
  package var publishedIDHash: UInt64 = 0
  package var publishedChildrenHash: UInt64 = 0
  package var childrenHashSince: UInt64 = 0
  /// Whether the host keeps state in this fiber's element (`publishedOwnsState`) or anywhere below it
  /// (`publishedHostOwned`): such a fiber is visited by every publication, so that what Swift renders is written again.
  package var publishedOwnsState = false
  package var publishedHostOwned = false

  init(identity: FiberIdentity, node: _RenderNode, parent: Fiber?, stateStore: StateStore, structuralID: StructuralNodeID, version: UInt64) {
    self.version = version
    self.identity = identity; self.structuralID = structuralID; viewType = node.kind.displayName; renderNode = node; renderOwnerToken = node._renderOwnerToken; parentIdentity = parent?.identity; self.stateStore = stateStore; children = []
    node._seal()
    _RuntimeMemoryMetrics.recordFiberInit()
  }

  deinit {
    _RuntimeMemoryMetrics.recordFiberDeinit()
  }

  func update(with node: _RenderNode) {
    renderNode = node; viewType = node.kind.displayName; renderOwnerToken = node._renderOwnerToken
    node._seal()
  }

  func reparent(to parent: Fiber?) { parentIdentity = parent?.identity }
}

package enum Mutation {
  case insert(node: _RenderNode, parent: Fiber, index: Int)
  case remove(node: _RenderNode, parent: Fiber, index: Int)
  case update(previous: _RenderNode, new: _RenderNode, fiber: Fiber)
  case replace(previous: _RenderNode, new: _RenderNode, fiber: Fiber)
  case move(node: _RenderNode, parent: Fiber, from: Int, to: Int)
}

@MainActor
final class BindingRuntime {
  /// Subscription callbacks cannot capture `self` weakly in Embedded Swift.
  /// Keep invalidation state in a separate reference object instead. The
  /// runtime owns subscriptions and the callbacks own this box, but the box
  /// never points back to the runtime, so this does not form a retain cycle.
  private final class DirtySourceBox {
    var sources: Set<_StateSourceID> = []
  }

  private struct CellKey: Equatable {
    let identity: FiberIdentity
    let source: _StateSourceID
    let operation: _LeafBindingOperation
  }

  private struct BindingCell {
    let key: CellKey
    var ownerID: StructuralNodeID
    var reader: () -> String
    var lastValue: String
    var live: Bool
    /// The last `sync` that found the cell's binding on its fiber.
    var seenPass: UInt64
  }

  private let store: StateStore
  private var cells: [BindingCell?] = []
  private var free: [Int] = []
  /// The cells of each fiber, by its identity: a fiber declares a binding or two, so a cell is found by scanning its
  /// fiber's few. A table keyed by identity rather than by `CellKey` shares its code with the framework's other
  /// identity tables (Embedded Swift emits the hashed-collection code once per key and value type).
  private var indices: [FiberIdentity: [Int]] = .init()
  /// Counts `sync` calls; a cell whose `seenPass` is behind it after the walk is no longer declared.
  private var pass: UInt64 = 0
  private var sourceCells: [_StateSourceID: [Int]] = .init()
  private var sourceSubscriptions: [_StateSourceID: _StateSubscription] = .init()
  private let dirtySourceBox = DirtySourceBox()
  private var dirtySources: Set<_StateSourceID> {
    get { dirtySourceBox.sources }
    set { dirtySourceBox.sources = newValue }
  }
  private(set) var staleGenerationSkips = 0

  init(store: StateStore) { self.store = store }

  isolated deinit {
    // Cells are value records inside the runtime arena, so no class deinit is
    // available to observe their release. Account for the live slots when a
    // tree is torn down (navigation/session disposal) as well as during sync.
    for cell in cells where cell?.live == true {
      _RuntimeMemoryMetrics.recordBindingCellRelease()
    }
  }

  var hasDirtyLeaf: Bool {
    !dirtySources.isEmpty && !store._hasDirtyStructuralSource()
  }

  /// Leaf work that remains meaningful after a structural pass has cleared
  /// StateStore's dirty-source bits. A structural source is already encoded
  /// by that pass's packed mutations and must not be replayed as a direct DOM
  /// update merely because another leaf source was dirty in the same turn.
  var hasDirtyLeafOnly: Bool {
    dirtySources.contains { !store._isStructural($0) }
  }

  func sync(root: Fiber) {
    pass &+= 1
    var provenSources = Set<_StateSourceID>()
    collect(root, provenSources: &provenSources)

    // Retire the cells no fiber declared in this pass.
    var changed: [(identity: FiberIdentity, indices: [Int])] = []
    for (identity, candidates) in indices where candidates.contains(where: { !isCurrent($0) }) {
      changed.append((identity, candidates))
    }
    for (identity, candidates) in changed {
      var kept: [Int] = []
      for index in candidates {
        if isCurrent(index) { kept.append(index) } else { retireCell(at: index) }
      }
      indices[identity] = kept.isEmpty ? nil : kept
    }

    sourceCells.removeAll(keepingCapacity: true)
    for (index, cell) in cells.enumerated() {
      guard let cell, cell.live else { continue }
      sourceCells[cell.key.source, default: []].append(index)
    }
    let staleSources = sourceSubscriptions.keys.filter { sourceCells[$0] == nil }
    for source in staleSources {
      sourceSubscriptions.removeValue(forKey: source)
    }
    store._endRenderPass(provenLeafSources: provenSources)
  }

  /// Whether the cell at `index` was declared in the current pass.
  private func isCurrent(_ index: Int) -> Bool {
    index < cells.count && cells[index]?.seenPass == pass
  }

  private func index(of key: CellKey) -> Int? {
    guard let candidates = indices[key.identity] else { return nil }
    for index in candidates where index < cells.count && cells[index]?.key == key { return index }
    return nil
  }

  private func removeIndex(of key: CellKey) -> Int? {
    guard var candidates = indices[key.identity],
          let position = candidates.firstIndex(where: { $0 < cells.count && cells[$0]?.key == key }) else { return nil }
    let index = candidates.remove(at: position)
    indices[key.identity] = candidates.isEmpty ? nil : candidates
    return index
  }

  private func collect(_ root: Fiber, provenSources: inout Set<_StateSourceID>) {
    var pending = [root]
    while let fiber = pending.popLast() {
      for descriptor in fiber.renderNode.leafBindings {
        let key = CellKey(identity: fiber.identity, source: descriptor.sourceID, operation: descriptor.operation)
        provenSources.insert(descriptor.sourceID)
        let value = descriptor.value()
        if let index = index(of: key), cells[index]?.ownerID == fiber.structuralID {
          cells[index]!.reader = descriptor.value
          cells[index]!.live = true
          cells[index]!.seenPass = pass
          // A structural pass has already committed the semantic value to the
          // DOM, so it is always the new baseline. Direct leaf commits do not
          // call sync and therefore retain their own previous-value comparison.
          // Preserve that comparison for a concurrently dirty, leaf-only source;
          // the browser host drains it after the structural batch. Structural
          // sources are already represented by the packed semantic mutations.
          if !dirtySources.contains(key.source) || store._isStructural(key.source) {
            cells[index]!.lastValue = value
          }
        } else {
          if let previousIndex = removeIndex(of: key) {
            retireCell(at: previousIndex)
          }
          let index: Int
          if let reused = free.popLast() {
            index = reused
          } else {
            index = cells.count
            cells.append(nil)
          }
          cells[index] = BindingCell(
            key: key, ownerID: fiber.structuralID, reader: descriptor.value, lastValue: value, live: true, seenPass: pass
          )
          _RuntimeMemoryMetrics.recordBindingCellInit()
          indices[key.identity, default: []].append(index)
        }
        if sourceSubscriptions[descriptor.sourceID] == nil {
          let dirtySourceBox = self.dirtySourceBox
          let sourceID = descriptor.sourceID
          sourceSubscriptions[sourceID] = store._subscribe(sourceID) {
            dirtySourceBox.sources.insert(sourceID)
          }
        }
      }
      pending.append(contentsOf: fiber.children.reversed())
    }
  }

  func drain(arena: StructuralArena) -> [_LeafUpdate] {
    guard hasDirtyLeaf else { return [] }
    var updates: [_LeafUpdate] = []
    for source in dirtySources {
      for index in sourceCells[source] ?? [] {
        guard index < cells.count, var cell = cells[index], cell.live else { continue }
        // A generational structural ID is sufficient to prove that the
        // original logical owner is still attached. This avoids recursively
        // searching the whole Fiber graph once per dirty BindingCell while
        // still rejecting callbacks from removed/recycled Fibers.
        guard arena.isLive(cell.ownerID) else {
          staleGenerationSkips += 1
          continue
        }
        let value = cell.reader()
        if value != cell.lastValue {
          cell.lastValue = value
          cells[index] = cell
          updates.append(_LeafUpdate(fiberIdentity: cell.key.identity, structuralID: cell.ownerID, operation: cell.key.operation, value: value))
        }
      }
    }
    dirtySources.removeAll(keepingCapacity: true)
    store._clearDirtySources()
    return updates
  }

  @inline(__always)
  private func retireCell(at index: Int) {
    guard index >= 0, index < cells.count, cells[index] != nil else { return }
    cells[index] = nil
    free.append(index)
    _RuntimeMemoryMetrics.recordBindingCellRelease()
  }
}

/// The canonical runtime representation and reconciler for SwiftUIWeb.
@MainActor
package final class FiberTree {
  package private(set) var root: Fiber
  private var rootView: AnyView
  private var environment: EnvironmentValues
  private var environmentRevision: UInt64
  private let stateStore: StateStore
  private let renderOwnerRegistry: _RenderOwnerRegistry
  /// The owner registry, for tests that check which owners stay registered.
  var _ownerRegistryForTesting: _RenderOwnerRegistry { renderOwnerRegistry }
  private let structuralArena: StructuralArena
  private let bindingRuntime: BindingRuntime
  // Owner and identity routing are hot paths during targeted Observation
  // updates. Keep direct indexes instead of walking the retained tree.
  private var fibersByIdentity: [FiberIdentity: Fiber] = .init()
  /// The owner registry's size (see `_RenderOwnerRegistry._registeredOwnerCount`).
  package var _registeredOwnerCount: Int { renderOwnerRegistry._registeredOwnerCount }
  private var fibersByOwnerToken: [UInt64: Fiber] = .init()
  /// `_RenderNode.sealedWrites` when the pass being reconciled started to render, and whether its render wrote a node a
  /// Fiber holds (a modifier writing into the content it wraps): then a reused node is not taken for unchanged. The
  /// reconcile's own writes (the handlers it moves onto the node it keeps) do not count.
  private var sealedWritesAtRender = 0
  private var renderWroteSealedNodes = false
  private func noteRenderEnded() { renderWroteSealedNodes = _RenderNode.sealedWrites != sealedWritesAtRender }
  /// The tokens Fibers gave up while a pass reconciled (`updateFiber`); nil outside one.
  private var givenUpOwnerTokens: [UInt64]?
  private var ownerPathsByToken: [UInt64: _FiberPath] = .init()
  private var ownerTokensByPath: [_FiberPath: Set<UInt64>] = .init()
  /// A render-owner token can outlive the Fiber it was originally attached
  /// to by one observation turn. Preserve that Fiber's structural identity
  /// for a bounded window so a publication can route to the nearest mounted
  /// owner without guessing from _RenderContext paths (which do not mirror the
  /// retained Fiber key path).
  private let retiredOwnerIdentityLimit = 4096
  private var retiredOwnerIdentities: [UInt64: _FiberPath] = .init()
  private var retiredOwnerIdentityTokens: [UInt64] = []
  private var retiredOwnerIdentityCursor = 0
  private let preferenceStore: _PreferenceStore
  private let layoutCacheStore: _LayoutCacheStore
  private let splitViewStateStore: _SplitViewStateStore
  /// The browser host may provide the current viewport as the root proposal.
  /// This remains renderer-owned so native/static callers keep the historical
  /// unspecified root proposal unless they explicitly opt into the SPI hook.
  private var rootLayoutProposal: ProposedViewSize?
  private let deferLazyCollections: Bool
  /// Fingerprints are intentionally bounded. Dynamic-but-untracked values are
  /// never used to bypass evaluation; they merely produce different keys and
  /// therefore do not grow this cache without limit.
  private var staticTemplateKeys: Set<String> = []
  /// Each distinct static-template description and the number naming it. A node's key is its number, and a parent's
  /// description holds its children's numbers, not their whole keys, so a key is the size of one node, not of its
  /// subtree. Numbers are never reused: past the limit the table starts again empty, and a description seen again gets a
  /// new number, which only costs one reuse.
  private var staticTemplateNumbers: [String: Int] = .init()
  private var nextStaticTemplateNumber = 0
  private let staticTemplateNumberLimit = 65_536
  private let staticTemplateCacheLimit = 2048
  private var externalInvalidationHandler: (() -> Void)? = nil
  private var observationInvalidationPending = false
  private var disposed = false
  /// An external host (the browser session, or a native embedding) may need
  /// to reconcile the tree after a state write. Keep the semantic snapshot
  /// dirty until that host asks for it; this preserves the old DOM as the
  /// baseline for an incremental commit while `renderNode` remains
  /// synchronous for native callers.
  private var externalInvalidationPending = false
  /// Browser hosts reconcile on a later event-loop turn so several writes can
  /// be coalesced against the DOM snapshot that is currently mounted. Native
  /// embedders keep the historical synchronous behavior unless they opt into
  /// this deferred mode.
  private var deferExternalInvalidation = false
  /// State writes can happen more than once during a single browser event
  /// (for example, a sidebar action may update both its selection and its
  /// path). Reconcile only after the event has finished so the host commits
  /// one coherent snapshot instead of applying the last mutation batch to a
  /// DOM that still represents the first intermediate state.
  private var deferredDispatchInvalidation = false
  // State writes performed by a DOM event are committed by the browser host
  // immediately after dispatch. Suppress only the host callback for that
  // synchronous window; the retained Fiber snapshot is still updated so
  // native callers and tests observe the new value immediately.
  private var dispatchDepth = 0
  /// Async lifecycle work can publish Observation changes while a structural
  /// commit is reconciling newly mounted views. Queue those changes until the
  /// current dependency pass has closed instead of starting a
  /// nested pass from inside reconciliation.
  private var reconciliationDepth = 0
  /// `appear` callbacks requested while a pass is reconciling. They run once
  /// the outermost pass has committed, like effects after a commit: state they
  /// write is then an ordinary, precisely routed invalidation instead of a
  /// nested write that can only fall back to re-rendering the whole root.
  private var pendingAppearNodes: [_RenderNode] = []
  /// Owners invalidated while they sat inside an inactive tab or navigation
  /// panel. Nobody can see them, so re-rendering waits until the panel is
  /// shown again (or a root pass renders everything anyway).
  private var deferredHiddenOwners: Set<FiberIdentity> = []
  private var leafInvalidationPending = false
  private var subtreeInvalidationPending = false
  private var pendingSubtreeOwnerTokens: Set<UInt64> = []
  /// State scopes retired inside `releasingStateScopes`, released together when the outermost one returns.
  private var pendingStateScopeReleases: [String] = []
  private var stateScopeReleaseDepth = 0
  private var packedMutationBufferPrimed = false
  package private(set) var metrics = _FiberRuntimeMetrics()
  /// Change clock. Fibers touched while it holds a value carry that value in
  /// `version`; publishing a snapshot advances it so later changes compare
  /// greater than everything already published.
  package private(set) var _epoch: UInt64 = 1
  /// Returns the epoch a snapshot covers and starts a new one.
  package func _advanceEpoch() -> UInt64 {
    let covered = _epoch
    _epoch += 1
    return covered
  }
  package var _liveStructuralNodeCount: Int { structuralArena.liveCount }
  package var _runtimeDiagnostics: _RuntimeDiagnostics {
    _RuntimeDiagnostics(
      liveNodes: UInt64(structuralArena.liveCount),
      retainedSlots: UInt64(structuralArena.capacity),
      dependencyEdges: UInt64(stateStore._dependencies.edgeCount)
    )
  }
  package var _observationDiagnostics: _FiberObservationDiagnostics {
    let state = stateStore._observationDiagnostics
    let candidateOwners = pendingSubtreeOwnerTokens.sorted()
    let (minimumOwners, staleOwner) = minimumPendingSubtreeOwnerTokens()
    let rootFallback = state.plan == .root ||
      (((externalInvalidationPending || observationInvalidationPending) && !subtreeInvalidationPending) || staleOwner)
    return _FiberObservationDiagnostics(
      stateStore: state,
      candidateSubtreeOwners: candidateOwners,
      pendingSubtreeOwners: minimumOwners,
      rootFallbackPending: rootFallback,
      disposed: disposed
    )
  }
  package func _childIDs(of fiber: Fiber) -> [StructuralNodeID] {
    try! structuralArena.children(of: fiber.structuralID)
  }
  package private(set) var lastMutations: [Mutation] = []
  /// Renderer-internal semantic mutation storage. The object is reused across
  /// commits; callers must consume it before the next update begins.
  package private(set) var _lastPackedMutations: _PackedMutationBuffer = _PackedMutationBuffer()
  /// Turns packed-mutation recording on or off for this tree (on by default).
  /// A renderer that never reads `_lastPackedMutations` (the Embedded browser)
  /// switches it off so every reconcile skips building a protocol nobody consumes.
  package func _setRecordsPackedMutations(_ enabled: Bool) {
    _lastPackedMutations.isRecording = enabled
  }

  isolated deinit {
    _dispose()
  }

  /// Explicitly tears down a tree before releasing the last host reference.
  /// Embedded Swift cannot use weak captures to break the invalidation cycle,
  /// so browser/session hosts must call this when replacing a root tree.
  package func _dispose() {
    guard !disposed else { return }
    disposed = true
    stateStore._dispose()
    externalInvalidationHandler = nil
    observationInvalidationPending = false
    externalInvalidationPending = false
    deferredDispatchInvalidation = false
    leafInvalidationPending = false
    subtreeInvalidationPending = false
    pendingSubtreeOwnerTokens.removeAll(keepingCapacity: false)
    retiredOwnerIdentities.removeAll(keepingCapacity: false)
    retiredOwnerIdentityTokens.removeAll(keepingCapacity: false)
    retiredOwnerIdentityCursor = 0
    // A context retained by an external adapter must not keep executable
    // owner callbacks alive after their tree has ended.
    renderOwnerRegistry._removeAll(keepingCapacity: false)
    // No future host commit can consume these compatibility records. Release
    // their _RenderNode side-table references at the same lifecycle boundary
    // so an explicitly disposed session cannot retain the previous batch.
    lastMutations.removeAll(keepingCapacity: false)
    _lastPackedMutations.reset()
    // Retained-tree shape is a diagnostic sample for the most recently
    // observed tree. Clear it when that tree is disposed so a navigation or
    // session teardown cannot look like a retained _RenderNode leak.
    _RuntimeMemoryMetrics.recordRetainedRenderNodeBytes(0)
  }
  package var _isDisposed: Bool { disposed }
  package var renderNode: _RenderNode {
    if disposed { return root.renderNode }
    if deferredDispatchInvalidation, dispatchDepth == 0 {
      deferredDispatchInvalidation = false
      if subtreeInvalidationPending {
        _ = updateRetainedSubtrees()
      } else if !_hasPendingLeafUpdates {
        // A proven control binding is fully represented by the retained
        // leaf cell; do not turn its host publish into a root body pass.
        metrics.deferredRootPasses += 1
        _ = updateRetainedRoot()
      }
    }
    if leafInvalidationPending {
      flushLeafUpdatesIntoSnapshot()
    }
    // Observation callbacks fire from a model's willSet hook. Defer the
    // actual Fiber evaluation until the next snapshot is requested so the
    // getter sees the model's new value (and remains synchronous for native
    // hosts and tests).
    if observationInvalidationPending {
      observationInvalidationPending = false
      if subtreeInvalidationPending {
        _ = updateRetainedSubtrees()
      } else {
        metrics.observationRootPasses += 1
        _ = updateRetainedRoot()
      }
    }
    if externalInvalidationPending {
      externalInvalidationPending = false
      metrics.externalRootPasses += 1
      _ = updateRetainedRoot()
    }
    if subtreeInvalidationPending {
      _ = updateRetainedSubtrees()
    }
    return root.renderNode
  }

  package convenience init<V: View>(_ view: V, environment: EnvironmentValues = .init()) {
    self.init(view, environment: environment, deferLazyCollections: true, rootLayoutProposal: nil)
  }

  /// Renderer-only construction hook. Browser-oriented Fiber trees defer lazy
  /// rows; static/WASI serializers opt out while keeping that policy out of
  /// the SwiftUI-facing initializer.
  package init<V: View>(
    _ view: V,
    environment: EnvironmentValues = .init(),
    deferLazyCollections: Bool,
    rootLayoutProposal: ProposedViewSize? = nil,
    startLifecycle: Bool = true
  ) {
    rootView = AnyView(view)
    self.environment = environment
    self.environmentRevision = environment._revision
    self.stateStore = StateStore()
    self.renderOwnerRegistry = _RenderOwnerRegistry()
    self.preferenceStore = _PreferenceStore()
    self.deferLazyCollections = deferLazyCollections
    self.structuralArena = StructuralArena()
    self.bindingRuntime = BindingRuntime(store: stateStore)
    self.layoutCacheStore = _LayoutCacheStore()
    self.splitViewStateStore = _SplitViewStateStore()
    self.rootLayoutProposal = rootLayoutProposal
    // Establish the object before invoking Observation tracking; the initial
    // render callback may capture `self` for subsequent invalidations.
    root = Fiber(identity: FiberIdentity(path: [_FiberKey("root")]), node: .empty(), parent: nil, stateStore: stateStore, structuralID: structuralArena.allocate(), version: 1)
    stateStore._beginRenderPass()
    let node = renderRoot()
    prepareStaticTemplates(in: node)
    root.update(with: node)
    root.children = makeChildren(of: root, node: node)
    refreshVolatility(root)
    indexSubtree(root)
    try! structuralArena.synchronize(liveIDs: collectStructuralIDs(root))
    metrics.retainedStructuralNodes = structuralArena.liveCount
    bindingRuntime.sync(root: root)
    sampleRetainedMemory()
    #if hasFeature(Embedded)
    stateStore.setInvalidationHandler {
      // Embedded Swift cannot capture a weak reference. The Embedded host
      // retains one application tree for its process lifetime.
      self.invalidateFromObservableObject()
    }
    #else
    stateStore.setInvalidationHandler { [weak self] in
      self?.invalidateFromObservableObject()
    }
    #endif
    if startLifecycle { invokeLifecycle(named: "appear", in: root.renderNode) }
  }

  /// Observable models can change outside a DOM event (for example, a timer
  /// or a host callback). Re-render the retained root view through Fiber so
  /// published changes preserve identity and produce normal mutations.
  private func invalidateFromObservableObject() {
    metrics.schedulerInvalidations += 1
    if reconciliationDepth > 0 {
      metrics.nestedChangeRootFallbacks += 1
      deferredDispatchInvalidation = true
      observationInvalidationPending = true
      externalInvalidationPending = true
      subtreeInvalidationPending = false
      pendingSubtreeOwnerTokens.removeAll(keepingCapacity: true)
      return
    }
    if dispatchDepth > 0 {
      deferredDispatchInvalidation = true
      if stateStore._hasPendingObservationInvalidation() { observationInvalidationPending = true }
      if bindingRuntime.hasDirtyLeaf { leafInvalidationPending = true }
      return
    }
#if hasFeature(Embedded)
    // Lowered @Observable members have source identities rather than native
    // registrar callbacks, so fan their dirty sources out to every observing
    // owner. Structural @State remains conservative for shared/unowned reads.
    if let owners = pendingOwnerTokensForInvalidation(), !owners.isEmpty {
      let shouldNotify = !subtreeInvalidationPending
      pendingSubtreeOwnerTokens.formUnion(owners)
      subtreeInvalidationPending = true
      if externalInvalidationHandler != nil {
        if deferExternalInvalidation {
          // A deferred host owns the current turn. Notify it once, then let
          // later writes only expand the pending owner set.
          if shouldNotify { externalInvalidationHandler?() }
        } else {
          _ = updateRetainedSubtrees()
          externalInvalidationHandler?()
        }
      } else {
        _ = updateRetainedSubtrees()
      }
      return
    }
    // A source read by multiple owners cannot be targeted safely. Preserve
    // correctness by reconciling the root once, while still avoiding this path
    // for the common single-owner model member case above.
    subtreeInvalidationPending = false
    pendingSubtreeOwnerTokens.removeAll(keepingCapacity: true)
    metrics.ownerRouteRootFallbacks += 1
    if externalInvalidationHandler != nil {
      if deferExternalInvalidation {
        let shouldNotify = !externalInvalidationPending
        externalInvalidationPending = true
        if shouldNotify { externalInvalidationHandler?() }
      } else {
        _ = updateRetainedRoot()
        externalInvalidationHandler?()
      }
    } else {
      _ = updateRetainedRoot()
    }
    return
#else
    if stateStore._hasPendingObservationInvalidation() {
      let shouldNotify = !observationInvalidationPending &&
        !externalInvalidationPending && !subtreeInvalidationPending
      observationInvalidationPending = true
      if let owners = pendingOwnerTokensForInvalidation(), !owners.isEmpty {
        pendingSubtreeOwnerTokens.formUnion(owners)
        subtreeInvalidationPending = true
      } else {
        subtreeInvalidationPending = false
        pendingSubtreeOwnerTokens.removeAll(keepingCapacity: true)
      }
      if shouldNotify { externalInvalidationHandler?() }
      return
    }
    if bindingRuntime.hasDirtyLeaf {
      leafInvalidationPending = true
      externalInvalidationHandler?()
      return
    }
    if let owners = stateStore._dirtySubtreeOwnerTokens(), !owners.isEmpty {
      let shouldNotify = !subtreeInvalidationPending
      pendingSubtreeOwnerTokens.formUnion(owners)
      subtreeInvalidationPending = true
      if externalInvalidationHandler != nil {
        if deferExternalInvalidation {
          if shouldNotify { externalInvalidationHandler?() }
        } else {
          _ = updateRetainedSubtrees()
          externalInvalidationHandler?()
        }
      } else {
        _ = updateRetainedSubtrees()
      }
      return
    }
    subtreeInvalidationPending = false
    pendingSubtreeOwnerTokens.removeAll(keepingCapacity: true)
    if externalInvalidationHandler != nil {
      if deferExternalInvalidation {
        let shouldNotify = !externalInvalidationPending
        externalInvalidationPending = true
        if shouldNotify { externalInvalidationHandler?() }
      } else {
        _ = updateRetainedRoot()
        externalInvalidationHandler?()
      }
      return
    }
    _ = updateRetainedRoot()
#endif
  }

  /// Renderer clock tick used by Embedded browser TimelineView.
  /// Live literals: a literal's value was replaced, which no view's inputs show, so every view is rendered again.
  #if DEBUG
  /// Development loop: the states of this tree that can be kept across a reload, as text (`_StateSnapshots`).
  package func _stateSnapshotText() -> String { _StateSnapshots.text(of: stateStore) }
  #endif

  @discardableResult package func _liveLiteralsChanged() -> [Mutation] {
    renderOwnerRegistry._forgetRenderedViews()
    return updateRetainedRoot()
  }

  @discardableResult package func _hostTimelineTick() -> [Mutation] {
    // A clock tick only changes TimelineView content. Re-evaluate the nearest
    // retained owner of each live timeline instead of the whole root so event
    // registrations and DOM outside the animation stay untouched between ticks.
    var tokens = Set<UInt64>()
    for fiber in fibersByIdentity.values {
      guard let timeline = fiber.renderNode._timeline, !timeline.paused else { continue }
      var cursor: Fiber? = fiber
      while let current = cursor, current.renderOwnerToken == nil {
        cursor = current.parentIdentity.flatMap { fibersByIdentity[$0] }
      }
      guard let token = cursor?.renderOwnerToken else { return updateRetainedRoot() }
      tokens.insert(token)
    }
    guard !tokens.isEmpty else { return updateRetainedRoot() }
    // Owners already waiting on an unpublished event stay queued; the tick only adds its own.
    pendingSubtreeOwnerTokens.formUnion(tokens)
    subtreeInvalidationPending = true
    return updateRetainedSubtrees()
  }

  /// Registers a host callback for Observation-driven invalidations that
  /// happen outside an explicit Fiber event. The callback is optional and
  /// does not replace Fiber's own retained-tree reconciliation.
  package func setExternalInvalidationHandler(_ handler: (() -> Void)?, deferUpdates: Bool = false) {
    deferExternalInvalidation = deferUpdates
    externalInvalidationHandler = handler
  }

  /// Completes the initial lifecycle pass after a host has installed its
  /// scheduler and external invalidation callback.
  package func _startLifecycle() {
    guard !disposed else { return }
    invokeLifecycle(named: "appear", in: root.renderNode)
  }

  /// Supplies the proposal available to the root custom `Layout`. Browser
  /// sessions update this once per coalesced resize frame; ordinary SwiftUI
  /// code never sees the hook and continues to use `ProposedViewSize` values
  /// produced by parent layouts.
  package func _setRootLayoutProposal(_ proposal: ProposedViewSize?) {
    guard !disposed else { return }
    rootLayoutProposal = proposal
  }

  /// Persists a split-view drag in normalized coordinates. Browser hosts call
  /// this after an interaction; the next coalesced render reconciles the same
  /// keyed child fibers with the updated geometry.
  package func _setSplitViewPositions(key: String, positions: [Double]) {
    guard !disposed else { return }
    splitViewStateStore.setValue(positions, for: key)
  }

  package func _splitViewPositions(key: String) -> [Double]? {
    splitViewStateStore.value(for: key)
  }

  /// Compatibility initializer for code that previously supplied a renderer;
  /// the renderer is now a serialization backend and does not participate in
  /// Fiber construction.
  package convenience init<R, V: View>(_ renderer: R, _ view: V, environment: EnvironmentValues = .init()) {
    self.init(view, environment: environment)
  }

  @discardableResult package func update<V: View>(_ view: V, environment: EnvironmentValues? = nil) -> [Mutation] {
    guard !disposed else { return [] }
    rootView = AnyView(view)
    if let environment {
      self.environment = environment
      environmentRevision = environment._revision
    }
    return updateRetainedRoot()
  }

  @discardableResult
  private func updateRetainedRoot(materialize: Bool = true) -> [Mutation] {
    guard !disposed else { return [] }
    defer { flushPendingAppear() }
    reconciliationDepth += 1
    stateStore._beginEffectDeferral()
    defer { reconciliationDepth -= 1; stateStore._endEffectDeferral() }
    metrics.schedulerStructuralFlushes += 1
    deferredDispatchInvalidation = false
    deferredHiddenOwners.removeAll(keepingCapacity: true)
    observationInvalidationPending = false
    externalInvalidationPending = false
    leafInvalidationPending = false
    subtreeInvalidationPending = false
    pendingSubtreeOwnerTokens.removeAll(keepingCapacity: true)
    preferenceStore.beginPass()
    // Owners rendered again at the same path keep their tokens (see `_beginReuse`).
    let keepsOwners = renderOwnerRegistry._beginRootPass()
    stateStore._beginRenderPass()
    var context = _RenderContext(environment: self.environment, stateStore: stateStore, preferenceStore: preferenceStore, _layoutCacheStore: layoutCacheStore, _splitViewStateStore: splitViewStateStore)
    context._layoutProposal = rootLayoutProposal
    context.lazyCollectionsEnabled = deferLazyCollections
    context._renderOwnerRegistry = renderOwnerRegistry
    sealedWritesAtRender = _RenderNode.sealedWrites
    let newNode = renderRoot(in: context)
    noteRenderEnded()
    renderOwnerRegistry._endReuse()
    prepareStaticTemplates(in: newNode)
    _lastPackedMutations.reset()
    _lastPackedMutations.setOwnerRoot(root)
    metrics.invalidatedOwners += 1
    metrics.invalidatedNodes += 1
    if keepsOwners { givenUpOwnerTokens = [] }
    reconcile(fiber: root, newNode: newNode, parent: nil, index: 0, mutations: _lastPackedMutations)
    retireGivenUpOwnerTokens()
    try! structuralArena.synchronize(liveIDs: collectStructuralIDs(root))
    metrics.retainedStructuralNodes = structuralArena.liveCount
    bindingRuntime.sync(root: root)
    sampleRetainedMemory()
    let pendingLeafOnly = bindingRuntime.hasDirtyLeafOnly
    stateStore._clearDirtySources()
    // A full structural pass may have shared the turn with an unrelated leaf
    // source. Keep the leaf pending bit alive so the browser host can apply
    // that direct update after this packed structural batch.
    leafInvalidationPending = pendingLeafOnly
    let mutations = finalizePackedMutations(materialize: materialize)
    lastMutations = mutations
    return mutations
  }

  /// Materialize the compatibility enum only at the package adapter boundary.
  /// Reconciliation and browser-specific code can instead inspect
  /// `_lastPackedMutations` without paying for enum/associated-value storage.
  private func finalizePackedMutations(materialize: Bool = true) -> [Mutation] {
    if packedMutationBufferPrimed { metrics.packedMutationBufferReuses += 1 }
    packedMutationBufferPrimed = true
    metrics.packedMutationRecords += _lastPackedMutations.recordCount
    metrics.packedMutationBytes += _lastPackedMutations.storageByteCount
    guard materialize else {
      lastMutations.removeAll(keepingCapacity: true)
      return []
    }
    metrics.packedMutationMaterializations += 1
    return _lastPackedMutations.materialize()
  }

  /// Renderer-only update entry point. Browser hosts consume the packed
  /// buffer directly and therefore do not allocate the compatibility enum
  /// array at all. The returned object is valid until the next update on this
  /// tree. Public `update` continues to materialize `[Mutation]`.
  @discardableResult
  package func _updateForRenderer<V: View>(_ view: V, environment: EnvironmentValues? = nil) -> _PackedMutationBuffer {
    guard !disposed else { return _lastPackedMutations }
    rootView = AnyView(view)
    return _updateEnvironmentForRenderer(environment)
  }

  /// Reconciles the retained root with a new renderer environment without
  /// rebuilding the root view value. Browser viewport/theme callbacks arrive
  /// outside the original render pass; evaluating `app.body` again there can
  /// recreate property-wrapper values such as `@State` with their defaults.
  /// Keeping the existing `rootView` makes a resize, tab switch, or focus
  /// change an environment update rather than an implicit logout.
  @discardableResult
  package func _updateEnvironmentForRenderer(_ environment: EnvironmentValues?) -> _PackedMutationBuffer {
    guard !disposed else { return _lastPackedMutations }
    if let environment,
       environment._revision != environmentRevision,
       !stateStore._hasDirtySourcesOtherThanEnvironment(),
       !stateStore._hasPendingObservationInvalidation() {
      let oldRevision = environmentRevision
      self.environment = environment
      environmentRevision = environment._revision
      stateStore._markEnvironmentChanged(notify: false)
      if let owners = stateStore._dirtyEnvironmentOwnerTokens(), !owners.isEmpty {
        let allContextsSafe = renderOwnerRegistry._allContextsUseEnvironmentRevision(oldRevision)
        let safeOwners = renderOwnerRegistry._rebindEnvironment(from: oldRevision, to: environment)
        // Owners below a local `.environment(...)` modifier carry a different
        // context revision. If any environment reader is outside the safe
        // set, replay ancestor propagation through the root instead.
        if allContextsSafe && owners.isSubset(of: safeOwners) {
          pendingSubtreeOwnerTokens.formUnion(owners)
          subtreeInvalidationPending = true
          _ = updateRetainedSubtrees(materialize: false)
          return _lastPackedMutations
        }
      }
    } else if let environment {
      self.environment = environment
      environmentRevision = environment._revision
    }
    _ = updateRetainedRoot(materialize: false)
    return _lastPackedMutations
  }

  /// Explicit compatibility materialization for a renderer host that needs
  /// to inspect semantic cases (for example animation diagnostics).
  package func _materializeLastPackedMutations() -> [Mutation] {
    guard !disposed else { return [] }
    let mutations = _lastPackedMutations.materialize()
    lastMutations = mutations
    metrics.packedMutationMaterializations += 1
    return mutations
  }

  /// Releases references held only for the just-completed browser commit while
  /// retaining array capacity for the next frame. Browser hosts call this
  /// after DOM/lifecycle/animation work has consumed the packed side table;
  /// native callers retain the historical `lastMutations` inspection window.
  package func _releaseCommitStorage() {
    lastMutations.removeAll(keepingCapacity: true)
    _lastPackedMutations.reset()
  }

  /// Re-evaluates only retained erased-view owners whose structural dependency
  /// changed. Ambiguous sources never enter this path; callers fall back to a
  /// complete root pass, preserving SwiftUI correctness for shared/unknown
  /// dependencies.
  @discardableResult
  private func updateRetainedSubtrees(materialize: Bool = true) -> [Mutation] {
    guard !disposed else { return [] }
    guard subtreeInvalidationPending, !pendingSubtreeOwnerTokens.isEmpty else { return [] }
    defer { flushPendingAppear() }
    reconciliationDepth += 1
    stateStore._beginEffectDeferral()
    defer { reconciliationDepth -= 1; stateStore._endEffectDeferral() }
    metrics.schedulerSubtreeFlushes += 1
    deferredDispatchInvalidation = false
    observationInvalidationPending = false
    externalInvalidationPending = false
    leafInvalidationPending = false

    var targets: [(token: UInt64, fiber: Fiber)] = []
    var resolvedTokens = Set<UInt64>()
    var staleOwnerCount = 0
    for token in pendingSubtreeOwnerTokens {
      if let owner = findOwner(ownerToken: token) {
        if resolvedTokens.insert(owner.token).inserted {
          targets.append((owner.token, owner.fiber))
        }
      } else {
        staleOwnerCount += 1
      }
    }
    // Removed/lazy owner callbacks can outlive their mounted Fiber by one
    // observation turn. They cannot affect visible output; discard those
    // routes and keep updating the still-mounted owners for the same source.
    // Falling back to the root here made one stale reader rebuild every
    // visible row even when the active node owner was already known.
    if staleOwnerCount > 0 {
      metrics.staleSubtreeOwnerTokens += staleOwnerCount
    }
    // Owners inside an inactive panel are not visible: remember them and render
    // once the panel is active instead of on every write while it is hidden.
    if !targets.isEmpty {
      var visibleTargets: [(token: UInt64, fiber: Fiber)] = []
      for target in targets {
        if lifecycleIsVisible(in: target.fiber) {
          visibleTargets.append(target)
        } else {
          deferredHiddenOwners.insert(target.fiber.identity)
          metrics.deferredHiddenOwnerRenders += 1
        }
      }
      if visibleTargets.count != targets.count {
        targets = visibleTargets
        if targets.isEmpty {
          stateStore._clearDirtySources()
          subtreeInvalidationPending = false
          pendingSubtreeOwnerTokens.removeAll(keepingCapacity: true)
          _lastPackedMutations.reset()
          lastMutations.removeAll(keepingCapacity: true)
          return []
        }
      }
    }
    pendingSubtreeOwnerTokens = Set(targets.map { $0.token })
    guard !targets.isEmpty else {
      // If every route is detached, there is no active owner boundary to
      // update selectively. Preserve the correctness fallback in that case;
      // pruning is safe only when at least one mounted reader remains.
      return updateRetainedRoot(materialize: materialize)
    }
    metrics.subtreeOwnerInvalidations += targets.count
    metrics.invalidatedOwners += targets.count
    // If an owner and one of its descendants are both dirty, rendering the
    // owner subsumes the descendant and avoids duplicate body evaluations.
    targets.sort { $0.fiber.identity.fiberPath.count < $1.fiber.identity.fiberPath.count }
    var selected: [(token: UInt64, fiber: Fiber)] = []
    for target in targets {
      if selected.contains(where: { $0.fiber.identity.fiberPath.isPrefix(of: target.fiber.identity.fiberPath) }) { continue }
      selected.append(target)
    }
    _lastPackedMutations.reset()
    _lastPackedMutations.setOwnerRoot(root)
    for target in selected {
      metrics.invalidatedNodes += 1
      metrics.subtreeTargetPathDepthTotal += target.fiber.identity.fiberPath.count
      let replacing = collectOwnerTokens(in: target.fiber, skippingLazyRows: true)
      stateStore._beginSubtreeRenderPass(replacing: replacing)
      // The owners inside the target render again: each keeps its token when it registers at the same path, so
      // unchanged rows do not re-index (see `_beginReuse`). The target's own owner renders in place.
      var nested = replacing
      nested.remove(target.token)
      if let own = target.fiber.renderOwnerToken { nested.remove(own) }
      renderOwnerRegistry._beginReuse(nested)
      defer { renderOwnerRegistry._endReuse() }
      sealedWritesAtRender = _RenderNode.sealedWrites
      guard let newNode = renderOwnerRegistry._render(target.token) else {
        metrics.staleSubtreeRendererFallbacks += 1
        // A retained Fiber can outlive the matching owner closure for one
        // turn when structural replacement races an Observation callback.
        // Close its dependency pass before the correctness-preserving root
        // fallback starts a new pass; otherwise Embedded treats that fallback
        // as an illegal nested read pass and traps.
        stateStore._endSubtreeRenderPass(provenLeafSources: [])
        return updateRetainedRoot(materialize: materialize)
      }
      // Modifier layers share one node, and each erased boundary around it stamps its own view type as the
      // node's descriptor; the outermost one wins in a full render. Re-rendering an inner boundary alone
      // would stamp that boundary's (shorter) type instead, and the descriptor mismatch would replace the
      // whole subtree: new fibers, state and focus lost. The node keeps the role it already had.
      noteRenderEnded()
      if let previous = target.fiber.renderNode.descriptor { newNode.descriptor = previous }
      metrics.bodyEvaluations += 1
      let renderedNodeCount = countRenderNodes(newNode)
      metrics.renderNodeAllocations += renderedNodeCount
      metrics.subtreeTargetRenderNodeCount += renderedNodeCount
      prepareStaticTemplates(in: newNode)
      var provenLeafSources = Set<_StateSourceID>()
      collectLeafSources(newNode, into: &provenLeafSources)
      let parent = target.fiber.parentIdentity.flatMap { fiber(at: $0) }
      let index = parent?.children.firstIndex(where: { $0.identity == target.fiber.identity }) ?? 0
      // The owner's node sits under another key in its parent now (its body's top-level conditional took the other
      // branch, or its `.id` changed): it is another view, and only a pass over the parent puts it in place, as a new
      // fiber under its own identity. Reconciled here it would keep the old identity until such a pass replaced the
      // whole subtree, with new fibers and event routes while the page still sends events to the old ones.
      if parent != nil, (newNode.key ?? _FiberKey(index)) != (target.fiber.renderNode.key ?? _FiberKey(index)) {
        metrics.rekeyedOwnerRootFallbacks += 1
        stateStore._endSubtreeRenderPass(provenLeafSources: provenLeafSources)
        return updateRetainedRoot(materialize: materialize)
      }
      givenUpOwnerTokens = []
      reconcile(fiber: target.fiber, newNode: newNode, parent: parent, index: index, mutations: _lastPackedMutations)
      retireGivenUpOwnerTokens()
      propagateRenderedNodeToAncestors(from: target.fiber)
      stateStore._endSubtreeRenderPass(provenLeafSources: provenLeafSources)
    }
    // Only this owner's subtree was reconciled, so the arena is current without a walk of the whole tree.
    noteStructuralArenaCurrent()
    bindingRuntime.sync(root: root)
    sampleRetainedMemory()
    let pendingLeafOnly = bindingRuntime.hasDirtyLeafOnly
    stateStore._clearDirtySources()
    // A targeted structural pass may have shared the turn with an unrelated
    // leaf source. Keep the leaf pending bit alive for the browser's
    // post-structural direct-update phase (see BindingRuntime.sync).
    leafInvalidationPending = pendingLeafOnly
    subtreeInvalidationPending = false
    pendingSubtreeOwnerTokens.removeAll(keepingCapacity: true)
    promoteDeferredHiddenOwners()
    let mutations = finalizePackedMutations(materialize: materialize)
    lastMutations = mutations
    return mutations
  }

  /// Schedules the owners that were invalidated while hidden and whose panel
  /// is now visible; forgets those that no longer exist.
  private func promoteDeferredHiddenOwners() {
    guard !deferredHiddenOwners.isEmpty else { return }
    var tokens = Set<UInt64>()
    for identity in deferredHiddenOwners {
      guard let fiber = fibersByIdentity[identity] else { deferredHiddenOwners.remove(identity); continue }
      guard lifecycleIsVisible(in: fiber) else { continue }
      deferredHiddenOwners.remove(identity)
      if let token = fiber.renderOwnerToken { tokens.insert(token) }
    }
    guard !tokens.isEmpty else { return }
    pendingSubtreeOwnerTokens = tokens
    subtreeInvalidationPending = true
  }

  // MARK: Hover rules

  #if SWIFTUIWEB_RELEASE && !SWIFTUIWEB_RELEASE_HAS_HOVER
  // A release of an application whose code never writes `onHover` (`Tools/release-reachability.js`, feature `hover`)
  // learns no hovered look: a probe it meets anyway keeps its enter/leave events, so Swift answers that hover as it does
  // for one styles cannot describe, and the release does not carry the speculative render, the comparison and the rules.
  package func _resolveHover(for fiber: Fiber, deferringNew: Bool = false) -> Bool { false }
  package var _hasDeferredHover: Bool { false }
  package func _learnDeferredHover() {}
  package func _hoverRuleChanges(acked: UInt64) -> String? { nil }
  package func _hoverRulesPublished(epoch: UInt64) {}
  #else
  private struct HoverEntry {
    let node: ObjectIdentifier
    /// CSS that reproduces the hovered look, or nil when styles alone cannot.
    let css: String?
  }
  private var hoverEntries: [FiberIdentity: HoverEntry] = .init()
  private var hoverRulesDirty = false
  /// A short key per hovering fiber: what the host files that fiber's rules under.
  private var hoverKeys: [FiberIdentity: Int] = .init()
  private var nextHoverKey = 0
  /// The rules by key the host holds once it has committed every publication so far.
  private var hoverPublished: [Int: String] = .init()
  /// Changes by key (the new rules, or nil to remove them) published at `epoch` and not acknowledged yet, and the ones
  /// this pass found, published next (`_hoverRulesPublished`).
  private var hoverUnacknowledged: [Int: (css: String?, epoch: UInt64)] = .init()
  private var hoverChanges: [Int: String?] = .init()
  /// Hovering fibers met for the first time whose CSS is learned later (`_learnDeferredHover`), with the node they showed
  /// and the Fiber of the owner that declares the state, found then: by the deferred pass the probe's token may be retired
  /// while that Fiber stays.
  private var hoverDeferred: [FiberIdentity: (node: ObjectIdentifier, owner: FiberIdentity)] = .init()

  private func nodeIDSelector(_ fiber: Fiber) -> String {
    "[data-embedded-node-id^=\"\(fiber.structuralID.index):\(fiber.structuralID.generation):\"]"
  }

  /// Learns how `fiber` (which carries an `onHover(_assigning:)` probe) looks
  /// while hovered by rendering its owner once with the state flipped, and
  /// keeps the difference as CSS. Returns true when styles alone describe it,
  /// so the pointer events need not reach Swift.
  ///
  /// With `deferringNew`, a fiber that has no rules yet is not learned now: it keeps its pointer events (Swift answers its
  /// hover, as for one styles cannot describe) until `_learnDeferredHover`. Learning renders the owner a second time, and a
  /// list that filters while typing brings back dozens of cards at every key.
  package func _resolveHover(for fiber: Fiber, deferringNew: Bool = false) -> Bool {
    let node = fiber.renderNode
    guard let probe = node._hoverProbe else { return false }
    if let cached = hoverEntries[fiber.identity], cached.node == ObjectIdentifier(node) { return cached.css != nil }
    // A hover whose owner cannot be found now is learned now, as before: the deferred pass would not find it either.
    if deferringNew, hoverEntries[fiber.identity] == nil, let owner = probe.ownerToken.flatMap({ findFiber(ownerToken: $0) }) {
      hoverDeferred[fiber.identity] = (ObjectIdentifier(node), owner.identity)
      return false
    }
    return learnHover(for: fiber, probe: probe, owner: nil)
  }

  private func learnHover(for fiber: Fiber, probe: _HoverProbe, owner: Fiber?) -> Bool {
    let node = fiber.renderNode
    let css = learnHoverCSS(for: fiber, probe: probe, owner: owner)
    let previousCSS = hoverEntries[fiber.identity]?.css
    hoverEntries[fiber.identity] = HoverEntry(node: ObjectIdentifier(node), css: css)
    if previousCSS != css { hoverRulesDirty = true }
    return css != nil
  }

  /// Whether some hovering fibers wait for `_learnDeferredHover`.
  package var _hasDeferredHover: Bool { !hoverDeferred.isEmpty }

  /// Learns the hover CSS `_resolveHover(for:deferringNew:)` deferred, for the fibers that still show the node they showed
  /// then, and marks the ones styles describe as changed: the next publication drops their pointer events and carries their
  /// rules. Called before a publication's snapshot, where the tree is current.
  package func _learnDeferredHover() {
    let pending = hoverDeferred
    hoverDeferred.removeAll()
    for (identity, entry) in pending {
      guard let fiber = fibersByIdentity[identity], ObjectIdentifier(fiber.renderNode) == entry.node,
            let probe = fiber.renderNode._hoverProbe else { continue }
      if learnHover(for: fiber, probe: probe, owner: fibersByIdentity[entry.owner]) { _markChanged(fiber) }
    }
  }

  private func learnHoverCSS(for trigger: Fiber, probe: _HoverProbe, owner: Fiber?) -> String? {
    guard let ownerToken = probe.ownerToken, let ownerFiber = owner ?? findFiber(ownerToken: ownerToken),
          ownerFiber.identity.fiberPath.isPrefix(of: trigger.identity.fiberPath) else { return nil }
    let previous = probe.setSilently(true)
    // A modifier applied after `onHover` makes the probe's own owner an inner
    // one whose closure holds values the body already evaluated; only the
    // outermost owner that returns this node re-runs the body with the flip.
    let renderToken = ownerFiber.renderOwnerToken ?? renderOwnerRegistry._outermostOwner(of: ownerToken)
    let hovered = renderOwnerRegistry._renderSpeculative(renderToken)
    _ = probe.setSilently(previous)
    // The Fiber tree holds the current children; a node's own `children` can lag.
    var fibersByNode: [ObjectIdentifier: Fiber] = .init()
    var toIndex = [ownerFiber]
    while let fiber = toIndex.popLast() {
      fibersByNode[ObjectIdentifier(fiber.renderNode)] = fiber
      toIndex.append(contentsOf: fiber.children)
    }
    guard let hovered,
          let differences = _hoverDifferences(normal: ownerFiber.renderNode, hovered: hovered, normalChildren: { node in
            guard let fiber = fibersByNode[ObjectIdentifier(node)] else { return node.children }
            return fiber.children.map { $0.renderNode }
          }) else { return nil }
    // A hovered render that looks exactly like the normal one is not proof that
    // hovering does nothing (the flipped state may not have reached the body), so
    // keep the pointer events with Swift instead of dropping the effect.
    if differences.isEmpty { return nil }
    var targets: [(selector: String, isOwnerRoot: Bool, declarations: _NodeValues, hasTransition: Bool, animation: String?)] = []
    for difference in differences {
      guard let target = fibersByNode[ObjectIdentifier(difference.normalNode)] else { return nil }
      targets.append((
        nodeIDSelector(target), target === ownerFiber, difference.declarations,
        difference.normalNode.styles["transition"] != nil || difference.normalNode.styles["transition-property"] != nil,
        difference.normalNode.attributes["data-animation-timing"]
      ))
    }
    return _hoverRuleCSS(ownerSelector: nodeIDSelector(ownerFiber), triggerSelector: nodeIDSelector(trigger), targets: targets)
  }

  /// The hover rule changes the host may not have yet, one a line: `+key\tcss` adds or replaces the rules of a key,
  /// `-key` removes them. Every change published after the epoch the host acknowledged is sent again until it is (a
  /// publication the host never committed would lose it), and nil when there is none. Only the hovering fibers that
  /// changed are sent, not the whole sheet: a list that filters while typing adds and removes a few cards' rules.
  package func _hoverRuleChanges(acked: UInt64) -> String? {
    for identity in hoverEntries.keys where fibersByIdentity[identity] == nil {
      hoverEntries.removeValue(forKey: identity)
      hoverRulesDirty = true
    }
    hoverUnacknowledged = hoverUnacknowledged.filter { $0.value.epoch > acked }
    if hoverRulesDirty {
      hoverRulesDirty = false
      var current: [Int: String] = .init()
      for (identity, entry) in hoverEntries {
        guard let css = entry.css else { continue }
        let key: Int
        if let known = hoverKeys[identity] { key = known } else { nextHoverKey += 1; key = nextHoverKey; hoverKeys[identity] = key }
        current[key] = css
      }
      for identity in hoverKeys.keys where hoverEntries[identity]?.css == nil { hoverKeys.removeValue(forKey: identity) }
      for (key, css) in current where hoverPublished[key] != css { hoverChanges[key] = css }
      for key in hoverPublished.keys where current[key] == nil { hoverChanges[key] = .some(nil) }
      hoverPublished = current
    }
    guard !hoverUnacknowledged.isEmpty || !hoverChanges.isEmpty else { return nil }
    var changes = hoverUnacknowledged.mapValues { $0.css }
    for (key, css) in hoverChanges { changes[key] = css }
    var out = ""
    for key in changes.keys.sorted() {
      // Each value is the rule (nil when it was removed); the key is always present.
      if case let css?? = changes[key] { out += "+\(key)\t\(css)\n" } else { out += "-\(key)\n" }
    }
    return out
  }

  /// Records the epoch the changes `_hoverRuleChanges` found in this pass are published at.
  package func _hoverRulesPublished(epoch: UInt64) {
    for (key, css) in hoverChanges { hoverUnacknowledged[key] = (css, epoch) }
    hoverChanges.removeAll(keepingCapacity: true)
  }
  #endif

  private func findFiber(ownerToken: UInt64) -> Fiber? { findOwner(ownerToken: ownerToken)?.fiber }

  /// The mounted fiber that answers `ownerToken` now, with its own token (the index keys every fiber by the token it holds,
  /// and a retired token is remapped only to a fiber that holds one), so callers never fall back to the token they asked for.
  private func findOwner(ownerToken: UInt64) -> (fiber: Fiber, token: UInt64)? {
    if let fiber = fibersByOwnerToken[ownerToken] { return (fiber, ownerToken) }
    let outermost = renderOwnerRegistry._outermostOwner(of: ownerToken)
    if outermost != ownerToken, let fiber = fibersByOwnerToken[outermost] { return (fiber, outermost) }
    // The token's old FiberIdentity is more precise than _RenderOwnerRegistry
    // context paths: those paths describe view-builder scopes and intentionally
    // differ from Fiber's retained semantic child keys. Match the old identity
    // first, then keep the context-path fallback for tokens not seen by this
    // FiberTree's bounded retirement index.
    if let oldIdentityPath = retiredOwnerIdentities[ownerToken],
       let exactFiber = fibersByIdentity[FiberIdentity(fiberPath: oldIdentityPath)],
       let activeToken = exactFiber.renderOwnerToken,
       renderOwnerRegistry._contains(activeToken) {
      return remapRetiredOwner(ownerToken, to: exactFiber)
    }
    if let oldIdentityPath = retiredOwnerIdentities[ownerToken],
       let fiber = nearestMountedRenderOwner(under: oldIdentityPath) {
      return remapRetiredOwner(ownerToken, to: fiber)
    }
    guard let path = renderOwnerRegistry._ownerPath(ownerToken),
          let fiber = nearestMountedRenderOwner(under: path) else { return nil }
    return remapRetiredOwner(ownerToken, to: fiber)
  }

  private func nearestMountedRenderOwner(under fiberPath: _FiberPath) -> Fiber? {
    let rootKey = _FiberKey("root")
    let path = fiberPath.keys
    let candidatePath = path.first == rootKey ? Array(path.dropFirst()) : path
    guard let identity = _nearestMountedRenderOwnerIdentity(
      path: candidatePath,
      rootKey: rootKey,
      isMountedRenderOwner: { candidate in
        guard let fiber = fibersByIdentity[candidate],
              let token = fiber.renderOwnerToken else { return false }
        return renderOwnerRegistry._contains(token)
      }
    ) else { return nil }
    return fibersByIdentity[identity]
  }

  private func remapRetiredOwner(_ ownerToken: UInt64, to fiber: Fiber) -> (fiber: Fiber, token: UInt64)? {
    guard let activeToken = fiber.renderOwnerToken else { return nil }
    if activeToken != ownerToken {
      stateStore._stageDependencyOwnerReplacements([ownerToken])
    }
    return (fiber, activeToken)
  }

  private func rememberRetiredOwnerIdentity(_ token: UInt64, path: _FiberPath) {
    guard retiredOwnerIdentities[token] == nil else { return }
    if retiredOwnerIdentityTokens.count < retiredOwnerIdentityLimit {
      retiredOwnerIdentityTokens.append(token)
    } else {
      let evicted = retiredOwnerIdentityTokens[retiredOwnerIdentityCursor]
      retiredOwnerIdentities.removeValue(forKey: evicted)
      retiredOwnerIdentityTokens[retiredOwnerIdentityCursor] = token
      retiredOwnerIdentityCursor = (retiredOwnerIdentityCursor + 1) % retiredOwnerIdentityLimit
    }
    retiredOwnerIdentities[token] = path
  }

  private func removeOwnerIndex(_ token: UInt64, for fiber: Fiber) {
    guard fibersByOwnerToken[token] === fiber else { return }
    fibersByOwnerToken.removeValue(forKey: token)
    if let path = ownerPathsByToken.removeValue(forKey: token) {
      ownerTokensByPath[path]?.remove(token)
      if ownerTokensByPath[path]?.isEmpty == true { ownerTokensByPath.removeValue(forKey: path) }
    }
    rememberRetiredOwnerIdentity(token, path: fiber.identity.fiberPath)
  }

  private func indexOwner(_ token: UInt64, for fiber: Fiber) {
    fibersByOwnerToken[token] = fiber
    guard let path = renderOwnerRegistry._ownerPath(token) else { return }
    ownerPathsByToken[token] = path
    ownerTokensByPath[path, default: []].insert(token)
  }

  private func indexSubtree(_ root: Fiber) {
    var pending = [root]
    while let fiber = pending.popLast() {
      fibersByIdentity[fiber.identity] = fiber
      if let token = fiber.renderOwnerToken { indexOwner(token, for: fiber) }
      pending.append(contentsOf: fiber.children.reversed())
    }
  }

  private func updateFiber(_ fiber: Fiber, with node: _RenderNode) {
    let previous = fiber.renderOwnerToken
    if let previous { removeOwnerIndex(previous, for: fiber) }
    fiber.update(with: node)
    if let token = fiber.renderOwnerToken { indexOwner(token, for: fiber) }
    if let previous, previous != fiber.renderOwnerToken { givenUpOwnerTokens?.append(previous) }
  }

  /// Retires the owner tokens Fibers gave up during a pass (`givenUpOwnerTokens`) that no Fiber holds again. A pass
  /// that renders a subtree again gives each Fiber below it the token of the owner that rendered it this time; the
  /// Fibers it removed retire their own (`releaseRenderOwner`), and the inner owners went when they were replaced
  /// (`_recordOuterOwner`). This took a second walk of the whole subtree, collecting its tokens after the reconcile
  /// to subtract them from the ones before.
  private func retireGivenUpOwnerTokens() {
    guard let tokens = givenUpOwnerTokens else { return }
    givenUpOwnerTokens = nil
    for token in tokens where fibersByOwnerToken[token] == nil { renderOwnerRegistry._remove(token) }
  }

  private func refreshOwnerToken(_ token: UInt64?, on fiber: Fiber) {
    guard fiber.renderOwnerToken != token else { return }
    fiber.renderNode._renderOwnerToken = token
    updateFiber(fiber, with: fiber.renderNode)
  }

  /// The owners of `fiber`'s subtree: its Fibers' tokens and the inner owners whose node each returned.
  /// The owners at and below `fiber`. A pass that renders an enclosing view again passes over the rows a lazy collection
  /// holds (the placeholder keeps them as they are): `skippingLazyRows` leaves their owners out, so the pass does not retire
  /// what they read (a cell's own `@State`) without reading it again.
  private func collectOwnerTokens(in fiber: Fiber, skippingLazyRows: Bool = false) -> Set<UInt64> {
    var result = Set<UInt64>()
    var pending = [fiber]
    while let current = pending.popLast() {
      if let token = current.renderOwnerToken { renderOwnerRegistry._ownersReturning(token, into: &result) }
      if skippingLazyRows, current.renderNode.lazyCollection != nil { continue }
      pending.append(contentsOf: current.children)
    }
    return result
  }

  private func minimumPendingSubtreeOwnerTokens() -> (owners: [UInt64], stale: Bool) {
    guard !pendingSubtreeOwnerTokens.isEmpty else { return ([], false) }
    var targets: [(token: UInt64, fiber: Fiber)] = []
    for token in pendingSubtreeOwnerTokens {
      guard let owner = findOwner(ownerToken: token) else { return ([], true) }
      targets.append((owner.token, owner.fiber))
    }
    targets.sort { lhs, rhs in
      if lhs.fiber.identity.fiberPath.count != rhs.fiber.identity.fiberPath.count {
        return lhs.fiber.identity.fiberPath.count < rhs.fiber.identity.fiberPath.count
      }
      return lhs.fiber.identity.description < rhs.fiber.identity.description
    }
    var selected: [(token: UInt64, fiber: Fiber)] = []
    for target in targets {
      if selected.contains(where: { $0.fiber.identity.fiberPath.isPrefix(of: target.fiber.identity.fiberPath) }) {
        continue
      }
      selected.append(target)
    }
    return (selected.map { $0.token }.sorted(), false)
  }

  /// Marks `fiber` and every ancestor as changed in the current epoch.
  private func _markChanged(_ fiber: Fiber) {
    var current: Fiber? = fiber
    while let visited = current {
      visited.version = _epoch
      current = visited.parentIdentity.flatMap { self.fiber(at: $0) }
    }
  }

  private static func nodeIsVolatile(_ node: _RenderNode) -> Bool {
    node.lazyCollection != nil
      || node._domView != nil
      || node.attributes["data-control-kind"] == "secure-field"
      || node.attributes["data-web-mount-key"] != nil
  }

  private func refreshVolatility(_ fiber: Fiber) {
    var volatile = Self.nodeIsVolatile(fiber.renderNode)
    if !volatile {
      for child in fiber.children where child.isVolatile { volatile = true; break }
    }
    fiber.isVolatile = volatile
  }

  private func propagateRenderedNodeToAncestors(from fiber: Fiber) {
    var child = fiber
    while let parentIdentity = child.parentIdentity, let parent = self.fiber(at: parentIdentity) {
      guard let index = parent.children.firstIndex(where: { $0.identity == child.identity }) else { break }
      parent.renderNode._replaceRetainedChild(at: index, with: child.renderNode)
      if child.version >= _epoch { parent.version = _epoch }
      if child.isVolatile { parent.isVolatile = true }
      child = parent
    }
  }

  /// Evaluates the retained root under Swift's Observation tracking when the
  /// module is available.  This is what makes models declared with the
  /// standard `@Observable` macro invalidate the same Fiber tree as
  /// `ObservableObject`/`@Published`, without exposing Observation in the
  /// SwiftUIWeb view API.  WASI/Embedded builds simply take the direct path.
  private func renderRoot(in context: _RenderContext? = nil) -> _RenderNode {
    metrics.bodyEvaluations += 1
    var renderContext = context ?? _RenderContext(environment: environment, stateStore: stateStore, preferenceStore: preferenceStore, _layoutCacheStore: layoutCacheStore, _splitViewStateStore: splitViewStateStore)
    if context == nil { renderContext._layoutProposal = rootLayoutProposal }
    renderContext.lazyCollectionsEnabled = deferLazyCollections
    // `rootView` is an erased owner just like every nested `AnyView`; its
    // `_render` path establishes Observation tracking per owner. Installing
    // the registry here means a second root-level Observation wrapper could
    // never run and would only duplicate the same one-shot tracking contract.
    renderContext._renderOwnerRegistry = renderOwnerRegistry
    let node = rootView._render(in: renderContext)
    metrics.renderNodeAllocations += countRenderNodes(node)
    return node
  }

  /// A loop rather than a recursion: the tree of a deep view hierarchy is as deep, and a recursion costs a
  /// WebAssembly frame per level (see `_RenderStaging`).
  private func countRenderNodes(_ root: _RenderNode) -> Int {
    var count = 0
    var pending = [root]
    while let node = pending.popLast() {
      count += 1
      pending.append(contentsOf: node.children)
    }
    return count
  }

  /// Estimates the retained semantic payload without walking allocator
  /// metadata. Swift/WASM does not expose portable per-object sizes, so this
  /// lower bound counts the class payload plus dynamic string/array contents.
  /// It is diagnostic-only and runs only when the opt-in memory probe is on.
  private func sampleRetainedMemory() {
    guard _RuntimeMemoryMetrics.isEnabled else { return }
    var fiberCount = 0
    var renderNodeCount = 0
    var fiberChildEdges = 0
    var renderNodeChildEdges = 0
    func stringBytes(_ value: String?) -> Int { value?.utf8.count ?? 0 }
    func mapBytes(_ values: _NodeValues) -> Int {
      values.reduce(0) { $0 + 32 + $1.key.utf8.count + $1.value.utf8.count }
    }
    func estimate(_ fiber: Fiber) -> Int {
      fiberCount += 1
      fiberChildEdges += fiber.children.count
      let node = fiber.renderNode
      renderNodeCount += 1
      renderNodeChildEdges += node.children.count
      var bytes = 192 + stringBytes(node.text) + stringBytes(node.descriptor)
      bytes += mapBytes(node.attributes) + mapBytes(node.styles)
      bytes += node.classes.reduce(0) { $0 + 24 + $1.utf8.count }
      bytes += node.children.count * MemoryLayout<_RenderNode>.stride
      bytes += node.events.reduce(0) { $0 + 64 + $1.key.utf8.count + $1.value.name.utf8.count }
      bytes += node.taskRegistrations.reduce(0) { $0 + 64 + $1.key.utf8.count + ($1.id?.utf8.count ?? 0) }
      bytes += node.leafBindings.count * 64
      bytes += node._layoutValues.count * 40 + node._layoutAlignmentGuides.count * 48
      bytes += node._canvasCommands.count * 32
      bytes += fiber.children.reduce(0) { $0 + estimate($1) }
      return bytes
    }
    _RuntimeMemoryMetrics.recordRetainedRenderNodeBytes(estimate(root))
    metrics.retainedFiberNodes = fiberCount
    metrics.retainedRenderNodeNodes = renderNodeCount
    metrics.retainedFiberChildEdges = fiberChildEdges
    metrics.retainedRenderNodeChildEdges = renderNodeChildEdges
  }

  /// Computes a canonical semantic fingerprint for a subtree.  Swift eagerly
  /// evaluates view values, so the renderer cannot safely skip an arbitrary
  /// application body without compiler metadata describing its captures.  A
  /// fingerprint is the conservative runtime fallback: only a complete,
  /// side-effect-free _RenderNode shape with no tracked state reads in its
  /// owner scope, and that is byte-for-byte equivalent to a retained shape,
  /// can be hoisted. Unknown/dynamic nodes simply receive no key and follow
  /// normal reconciliation.
  @discardableResult
  private func prepareStaticTemplates(in root: _RenderNode, inheritedDynamicOwner: Bool = false) -> String? {
    // A loop over an explicit stack rather than a recursion (see `countRenderNodes`): children first, then the node.
    struct Frame {
      let node: _RenderNode
      let ownerIsDynamic: Bool
      var next = 0
      var childKeys: [String?] = []
    }
    var stack = [Frame(node: root, ownerIsDynamic: staticTemplateOwnerIsDynamic(root, inherited: inheritedDynamicOwner))]
    var result: String?
    while let top = stack.last {
      let children = top.node.children
      if top.next < children.count {
        let child = children[top.next]
        stack[stack.count - 1].next += 1
        stack.append(Frame(node: child, ownerIsDynamic: staticTemplateOwnerIsDynamic(child, inherited: top.ownerIsDynamic)))
      } else {
        let done = stack.removeLast()
        let key = finishStaticTemplate(done.node, ownerIsDynamic: done.ownerIsDynamic, childKeys: done.childKeys)
        if stack.isEmpty { result = key } else { stack[stack.count - 1].childKeys.append(key) }
      }
    }
    return result
  }

  private func staticTemplateOwnerIsDynamic(_ node: _RenderNode, inherited: Bool) -> Bool {
    // Until compiler metadata can attach every @State read to the exact
    // erased owner, a tree that owns any State storage is conservatively kept
    // on the normal retained representation path. This avoids compacting a
    // dynamic interpolation merely because Swift formed it before its child
    // AnyView owner was installed.
    let treeHasState = stateStore._hasStateStorage()
    return inherited ||
      treeHasState ||
      (node._renderOwnerToken.map { stateStore._ownerReadSourcesDuringCurrentPass($0) } ?? false)
  }

  private func finishStaticTemplate(_ node: _RenderNode, ownerIsDynamic: Bool, childKeys: [String?]) -> String? {
    // Events, tasks, bindings and deferred collections all carry lifecycle or
    // state ownership.  Reusing their representation could transfer a
    // callback/controller to a different logical node, so they are never
    // classified as static. Host lifecycle annotations are likewise excluded
    // even when a backend has attached them as ordinary attributes.
    guard !ownerIsDynamic,
          node.events.isEmpty,
          node.taskRegistrations.isEmpty,
          node.leafBindings.isEmpty,
          node._dragSource == nil,
          node._dropTarget == nil,
          node._layoutValues.isEmpty,
          node._layoutRender == nil,
          node._layoutAlignmentGuides.isEmpty,
          node._layoutExplicitHorizontalAlignment == nil,
          node._layoutExplicitVerticalAlignment == nil,
          node._tableCellRender == nil,
          node._canvasCommands.isEmpty,
          node._canvasFingerprint == nil,
          node._timeline == nil,
          node.lazyCollection == nil,
          childKeys.allSatisfy({ $0 != nil }),
          !node.attributes.keys.contains(where: {
            $0.hasPrefix("data-web-mount") ||
            $0.hasPrefix("data-geometry-host")
          }) else {
      node._staticTemplateKey = nil
      return nil
    }

    // Instance-bound attributes (ids, host markers, presentation flags) are part of the key too. A retained node is
    // kept whenever the keys match, so an attribute left out of the key would never reach the DOM after a change.
    let attributes = node.attributes
      .sorted { $0.key == $1.key ? $0.value < $1.value : $0.key < $1.key }
      .map { lengthPrefixed($0.key) + lengthPrefixed($0.value) }
      .joined()
    let styles = node.styles
      .sorted { $0.key == $1.key ? $0.value < $1.value : $0.key < $1.key }
      .map { lengthPrefixed($0.key) + lengthPrefixed($0.value) }
      .joined()
    let classes = node.classes.map(lengthPrefixed).joined()
    let childDescription = childKeys.compactMap { $0 }.map(lengthPrefixed).joined()
    let keyDescription = node.key.map(fiberKeyDescription) ?? ""
    let descriptor = node.descriptor ?? ""
    let components = [
      node.kind.displayName,
      node.text ?? "",
      attributes,
      styles,
      classes,
      keyDescription,
      descriptor,
      childDescription
    ].map(lengthPrefixed).joined()
    let fingerprint = staticTemplateKey(for: components)
    node._staticTemplateKey = fingerprint
    metrics.staticTemplateCandidates += 1
    if staticTemplateKeys.contains(fingerprint) {
      metrics.staticTemplateHits += 1
    } else {
      metrics.staticTemplateMisses += 1
      if staticTemplateKeys.count < staticTemplateCacheLimit {
        staticTemplateKeys.insert(fingerprint)
      }
    }
    return fingerprint
  }

  private func lengthPrefixed(_ value: String) -> String {
    "\(value.utf8.count):\(value)"
  }

  /// The key naming one static-template description: equal descriptions get equal keys while the table holds them, and
  /// different ones never share one.
  private func staticTemplateKey(for description: String) -> String {
    if let number = staticTemplateNumbers[description] { return "t" + String(number) }
    if staticTemplateNumbers.count >= staticTemplateNumberLimit { staticTemplateNumbers.removeAll(keepingCapacity: true) }
    nextStaticTemplateNumber += 1
    staticTemplateNumbers[description] = nextStaticTemplateNumber
    return "t" + String(nextStaticTemplateNumber)
  }

  @discardableResult package func reconcile<V: View>(_ view: V, environment: EnvironmentValues? = nil) -> [Mutation] {
    update(view, environment: environment)
  }

  /// Mounts the current Fiber snapshot through a platform adapter. The
  /// adapter receives only backend-neutral RenderNodes, so browser bridges can
  /// stay outside the view/state implementation.
  package func mount<R: FiberRuntimeAdapter>(to adapter: R) {
    adapter.mount(root: root.renderNode)
  }

  /// Reconciles and commits one mutation batch. Keeping the commit as a
  /// generic operation avoids storing an existential adapter in every Fiber
  /// tree and lets Embedded Swift specialize the call site.
  @discardableResult
  package func update<V: View, R: FiberRuntimeAdapter>(
    _ view: V,
    environment: EnvironmentValues? = nil,
    to adapter: R
  ) -> [Mutation] {
    let mutations = update(view, environment: environment)
    adapter.apply(mutations)
    return mutations
  }

  @discardableResult
  package func reconcile<V: View, R: FiberRuntimeAdapter>(
    _ view: V,
    environment: EnvironmentValues? = nil,
    to adapter: R
  ) -> [Mutation] {
    update(view, environment: environment, to: adapter)
  }

  package func dispatch(event name: String, on node: _RenderNode? = nil) {
    guard !disposed else { return }
    let target = node ?? findNode(withEvent: name, in: root.renderNode)
    dispatchDepth += 1
    defer { dispatchDepth -= 1; if dispatchDepth == 0 { scheduleDeferredInvalidation() } }
    target?.events[name]?.action()
  }

  package func dispatch(event name: String, value: String, on node: _RenderNode? = nil) {
    guard !disposed else { return }
    let target = node ?? findNode(withEvent: name, in: root.renderNode)
    dispatchDepth += 1
    defer { dispatchDepth -= 1; if dispatchDepth == 0 { scheduleDeferredInvalidation() } }
    target?.events[name]?.valueAction?(value)
  }

  /// Resolves an event target by stable Fiber identity. A browser runtime can
  /// send a compact identity/path token back to Swift without passing a DOM
  /// object or rewalking the rendered HTML tree.
  package func dispatch(event name: String, at identity: FiberIdentity) {
    guard !disposed else { return }
    dispatchDepth += 1
    defer { dispatchDepth -= 1; if dispatchDepth == 0 { scheduleDeferredInvalidation() } }
    fiber(at: identity)?.renderNode.events[name]?.action()
  }

  package func dispatch(event name: String, value: String, at identity: FiberIdentity) {
    guard !disposed else { return }
    dispatchDepth += 1
    defer { dispatchDepth -= 1; if dispatchDepth == 0 { scheduleDeferredInvalidation() } }
    fiber(at: identity)?.renderNode.events[name]?.valueAction?(value)
  }

  /// Executes a host event while coalescing all state writes made by the
  /// action. Browser handlers often update more than one `@State` value; the
  /// browser host performs one reconciliation after this closure returns.
  /// Keeping the scope on FiberTree also covers handlers that are resolved by
  /// the browser adapter rather than by `dispatch(event:)` itself.
  package func performEvent(_ action: () -> Void) {
    guard !disposed else { return }
    dispatchDepth += 1
    defer { dispatchDepth -= 1; if dispatchDepth == 0 { scheduleDeferredInvalidation() } }
    action()
  }

  /// Converts coalesced event writes into a targeted owner request after the
  /// event's final state is visible. Shared/unknown dependencies remain on the
  /// existing root path.
  private func scheduleDeferredInvalidation() {
    guard dispatchDepth == 0, deferredDispatchInvalidation else { return }
    guard let owners = pendingOwnerTokensForInvalidation() else {
      // An earlier event of the same host batch (a GeometryReader report)
      // may have queued its own owner. A pending subtree request makes the
      // next snapshot skip the root pass this unroutable write needs, so
      // fall back to the root, which covers the queued owners too.
      if subtreeInvalidationPending {
        subtreeInvalidationPending = false
        pendingSubtreeOwnerTokens.removeAll(keepingCapacity: true)
        metrics.ownerRouteRootFallbacks += 1
      }
      return
    }
    if !owners.isEmpty {
      pendingSubtreeOwnerTokens.formUnion(owners)
      subtreeInvalidationPending = true
    }
  }

  private func pendingOwnerTokensForInvalidation() -> Set<UInt64>? {
    var owners = stateStore._observationOwnerTokens()
#if hasFeature(Embedded)
    let sourceCount = stateStore._pendingPublishedObservationSourceCount()
    let routing = _resolvePublishedObservationOwners(
      sourceCount: sourceCount,
      groups: stateStore._dirtyPublishedObservationOwnerGroups(),
      resolve: { token in
        let indexedOwner = fibersByOwnerToken[token] != nil
        let hasRetainedPath = renderOwnerRegistry._ownerPath(token) != nil
        guard let fiber = findFiber(ownerToken: token) else {
          if !hasRetainedPath {
            metrics.publishedObservationOwnerPathsUnavailable += 1
          } else {
            metrics.publishedObservationOwnerPathsNotMounted += 1
          }
          return nil
        }
        let activeToken = fiber.renderOwnerToken ?? token
        if !indexedOwner {
          if !hasRetainedPath {
            metrics.publishedObservationOwnerPathsUnavailable += 1
          } else {
            metrics.publishedObservationOwnerPathsNotMounted += 1
          }
          if activeToken != token { metrics.publishedObservationOwnerPathRemaps += 1 }
        }
        return activeToken
      }
    )
    let publishedOwners: Set<UInt64>
    switch routing {
    case .groupsUnavailable:
      if sourceCount > 0 {
        metrics.publishedObservationGroupsUnavailable += 1
        metrics.publishedObservationRouteMisses += 1
      }
      return nil
    case .sourceCountMismatch:
      if sourceCount > 0 {
        metrics.publishedObservationSourceCountMismatches += 1
        metrics.publishedObservationRouteMisses += 1
      }
      return nil
    case .groupsWithoutActiveOwners(let unresolvedOwnerTokens):
      metrics.publishedObservationGroupsWithoutActiveOwners += 1
      metrics.publishedObservationUnresolvedOwnerTokens += unresolvedOwnerTokens
      metrics.publishedObservationRouteMisses += 1
      return nil
    case .routed(let owners, let unresolvedOwnerTokens):
      metrics.publishedObservationUnresolvedOwnerTokens += unresolvedOwnerTokens
      publishedOwners = owners
    }
    metrics.publishedObservationTargets += publishedOwners.count
    owners.formUnion(publishedOwners)
    if stateStore._hasDirtyStructuralSource() {
      guard let structuralOwners = stateStore._dirtyStateSubtreeOwnerTokens() else {
        metrics.stateOwnerRouteMisses += 1
        return nil
      }
      owners.formUnion(structuralOwners)
    }
#else
    if stateStore._hasDirtyStructuralSource() {
      guard let structuralOwners = stateStore._dirtySubtreeOwnerTokens() else { return nil }
      owners.formUnion(structuralOwners)
    }
#endif
    return owners
  }

  /// Whether the latest state write is proven to affect only registered leaf
  /// bindings. Browser hosts use this to bypass body evaluation entirely.
  package var _hasPendingLeafUpdates: Bool {
    leafInvalidationPending && bindingRuntime.hasDirtyLeaf && !stateStore._hasPendingObservationInvalidation()
  }

  package var _hasPendingSubtreeInvalidation: Bool {
    subtreeInvalidationPending && !pendingSubtreeOwnerTokens.isEmpty
  }

  /// Whether the next snapshot has anything to render: an event wrote state, a model or a host measurement changed, or a
  /// pass was requested. Every invalidation reaches `invalidateFromObservableObject`, which records one of these, so an
  /// event that leaves this false changed nothing a publication would show.
  package var _hasPendingInvalidation: Bool {
    deferredDispatchInvalidation || observationInvalidationPending || externalInvalidationPending
      || leafInvalidationPending || subtreeInvalidationPending
  }

  /// Offers a key press to `node`, then to each of `enclosing` (innermost first) until one handles it, as SwiftUI sends
  /// `onKeyPress` from the focused view outward. Returns whether one did.
  package func dispatchKeyPress(_ press: String, on node: _RenderNode, enclosing: [_RenderNode]) -> Bool {
    _ = _KeyPressDispatch._consumeHandled()
    for target in [node] + enclosing where target.events["keyPress"]?.valueAction != nil {
      dispatch(event: "keyPress", value: press, on: target)
      if _KeyPressDispatch._consumeHandled() { return true }
    }
    return false
  }

  /// Browser hosts can inspect an incoming environment before choosing the
  /// leaf fast path. A pending environment change must be committed first;
  /// otherwise a simultaneous control write could return early and leave
  /// inherited values stale until an unrelated future event.
  package func _environmentChanged(to environment: EnvironmentValues) -> Bool {
    environment._revision != environmentRevision
  }

  /// Drains the coalesced leaf queue. A stale owner/generation is ignored, so
  /// a callback racing a structural replacement cannot mutate detached DOM.
  package func _drainLeafUpdates(preservingPackedMutations: Bool = false) -> [_LeafUpdate] {
    guard _hasPendingLeafUpdates else { return [] }
    metrics.schedulerLeafFlushes += 1
    let updates = bindingRuntime.drain(arena: structuralArena)
    metrics.bindingCellUpdates += updates.count
    metrics.staleGenerationSkips = bindingRuntime.staleGenerationSkips
    lastMutations.removeAll(keepingCapacity: true)
    if !preservingPackedMutations {
      _lastPackedMutations.reset()
    }
    leafInvalidationPending = false
    return updates
  }

  /// Applies proven leaf values to retained RenderNodes before a snapshot
  /// host serializes the tree. This keeps HTML snapshot clients from forcing a
  /// full body/reconcile pass for a TextField, Toggle, or other leaf-only edit.
  private func flushLeafUpdatesIntoSnapshot() {
    guard _hasPendingLeafUpdates else {
      leafInvalidationPending = false
      return
    }
    metrics.schedulerLeafFlushes += 1
    let updates = bindingRuntime.drain(arena: structuralArena)
    metrics.bindingCellUpdates += updates.count
    metrics.staleGenerationSkips = bindingRuntime.staleGenerationSkips
    for update in updates {
      guard let fiber = fiber(at: update.fiberIdentity),
            fiber.structuralID == update.structuralID else {
        metrics.staleGenerationSkips += 1
        continue
      }
      applyLeafUpdate(update, to: fiber.renderNode)
      _markChanged(fiber)
      // A select's value moves `selected` between its options' nodes, which are their own fibers' nodes: they changed
      // too, and a publisher that sends only what changed must see it.
      if case .property("value") = update.operation, case .element("select") = fiber.renderNode.kind {
        for child in fiber.children where child.renderNode.kind == .element("option") { _markChanged(child) }
      }
    }
    leafInvalidationPending = false
  }

  private func applyLeafUpdate(_ update: _LeafUpdate, to node: _RenderNode) {
    switch update.operation {
    case .textContent:
      if case .element("textarea") = node.kind {
        node.children = [.text(update.value)]
      } else {
        node.text = update.value
      }
    case .property(let name):
      if name == "value", case .element("textarea") = node.kind {
        // HTML represents a textarea's value as its text content. Writing a
        // value attribute leaves the browser property unchanged, so a retained
        // Fiber leaf update would otherwise be reverted on the next DOM patch.
        node.children = [.text(update.value)]
      } else if !(name == "value" && node._secureValue != nil) {
        node.attributes[name] = update.value.isEmpty ? nil : update.value
      }
      if name == "value", case .element("select") = node.kind {
        for option in node.children where option.kind == .element("option") {
          option.attributes["selected"] = option.attributes["value"] == update.value ? "selected" : nil
        }
      }
    case .attribute(let name):
      node.attributes[name] = update.value.isEmpty ? nil : update.value
    case .style(let name):
      node.styles[name] = update.value.isEmpty ? nil : update.value
    }
  }

  /// Drains a coalesced subtree invalidation for browser hosts. The returned
  /// mutation batch is committed against the retained DOM index exactly like a
  /// root pass, but body evaluation starts at the owning erased-view boundary.
  package func _drainSubtreeUpdates() -> [Mutation] {
    guard _hasPendingSubtreeInvalidation else { return [] }
    return updateRetainedSubtrees()
  }

  /// Browser counterpart of `_drainSubtreeUpdates` that keeps the semantic
  /// stream packed and avoids compatibility enum materialization.
  package func _drainPackedSubtreeUpdates() -> _PackedMutationBuffer {
    guard _hasPendingSubtreeInvalidation else {
      _lastPackedMutations.reset()
      _lastPackedMutations.setOwnerRoot(root)
      return _lastPackedMutations
    }
    _ = updateRetainedSubtrees(materialize: false)
    return _lastPackedMutations
  }

  /// Browser adapters report the number of concrete commit records they
  /// attempted. Keeping this hook in Fiber avoids coupling Core to DOM APIs
  /// while making the scheduler/DOM relationship visible to diagnostics.
  package func _recordDOMOperations(_ count: Int) {
    guard count > 0 else { return }
    metrics.domOperations += count
  }

  package func _recordBridgeSubmission(batches: Int, commands: Int, fallbacks: Int, indexRebuilds: Int = 0) {
    metrics.bridgeBatches += max(0, batches)
    metrics.bridgeCommands += max(0, commands)
    metrics.bridgeFallbackCalls += max(0, fallbacks)
    metrics.bridgeIndexRebuilds += max(0, indexRebuilds)
  }

  package func fiber(at identity: FiberIdentity) -> Fiber? {
    fibersByIdentity[identity]
  }

  private func releaseChildren(of fiber: Fiber) {
    for child in fiber.children { releaseSubtree(child) }
  }

  /// Calls `body` on every fiber of the subtree, each after its children and in sibling order: what a recursion does,
  /// without a WebAssembly frame per level of a tree that a deep view hierarchy makes as deep.
  private func forEachFiberChildrenFirst(_ root: Fiber, _ body: (Fiber) -> Void) {
    var stack: [(fiber: Fiber, next: Int)] = [(root, 0)]
    while let top = stack.last {
      let children = top.fiber.children
      if top.next < children.count {
        stack[stack.count - 1].next += 1
        stack.append((children[top.next], 0))
      } else {
        stack.removeLast()
        body(top.fiber)
      }
    }
  }

  private func releaseStateScopes(for fiber: Fiber, preservingStateScopes activePaths: Set<_FiberPath>) {
    var paths = fiber.renderNode._stateScopePaths
    if let token = fiber.renderOwnerToken,
       let path = renderOwnerRegistry._ownerPath(token) {
      if !paths.contains(path) { paths.append(path) }
    }
    for path in paths where !activePaths.contains(path) {
      if ownerTokensByPath[path]?.contains(where: { $0 != fiber.renderOwnerToken }) == true {
        continue
      }
      // The scope is named by the path's text for state and tasks, and by its compact id for what the motion engine keeps.
      var scopes = [path.description]
      if let compact = path._knownCompactID(in: stateStore._compactPathIDs) { scopes.append(compact) }
      if stateScopeReleaseDepth > 0 { pendingStateScopeReleases.append(contentsOf: scopes) }
      else { stateStore._releaseStateScopes(atPathPrefixes: scopes) }
    }
  }

  /// Releases the state scopes `body` retires in one pass over the state store, when it returns: a subtree leaving the
  /// tree took one pass per Fiber, each comparing every state key with that Fiber's path (a fifth of a
  /// section change in a large app).
  private func releasingStateScopes(_ body: () -> Void) {
    stateScopeReleaseDepth += 1
    body()
    stateScopeReleaseDepth -= 1
    guard stateScopeReleaseDepth == 0, !pendingStateScopeReleases.isEmpty else { return }
    stateStore._releaseStateScopes(atPathPrefixes: pendingStateScopeReleases)
    pendingStateScopeReleases.removeAll(keepingCapacity: true)
  }

  private func releaseRenderOwner(for fiber: Fiber) {
    guard let token = fiber.renderOwnerToken else { return }
    renderOwnerRegistry._remove(token)
    removeOwnerIndex(token, for: fiber)
  }

  private func releaseOwnerState(for fiber: Fiber) {
    releaseOwnerState(for: fiber, preservingStateScopes: [])
  }

  private func releaseOwnerState(for fiber: Fiber, preservingStateScopes activePaths: Set<_FiberPath>) {
    releaseStateScopes(for: fiber, preservingStateScopes: activePaths)
    releaseRenderOwner(for: fiber)
  }

  private func releaseSubtree(_ root: Fiber) {
    // Debug hook intentionally left silent in release builds; the arena
    // generation guard below makes double releases harmless.
    releasingStateScopes {
      forEachFiberChildrenFirst(root) { fiber in
        releaseOwnerState(for: fiber)
        if fibersByIdentity[fiber.identity] === fiber { fibersByIdentity.removeValue(forKey: fiber.identity) }
        metrics.removedNodes += 1
        structuralArena.release(fiber.structuralID)
      }
    }
  }

  private func releaseSubtree(_ root: Fiber, preservingStateScopes activePaths: Set<_FiberPath>) {
    releasingStateScopes {
      forEachFiberChildrenFirst(root) { fiber in
        releaseOwnerState(for: fiber, preservingStateScopes: activePaths)
        if fibersByIdentity[fiber.identity] === fiber { fibersByIdentity.removeValue(forKey: fiber.identity) }
        metrics.removedNodes += 1
        structuralArena.release(fiber.structuralID)
      }
    }
  }

  /// Publishes the arena's live count after a pass that reconciled one owner's subtree instead of the whole tree.
  /// No sweep is needed there: `allocate` registers each Fiber the reconcile creates, `setChildren` records where it
  /// sits, and `releaseSubtree` retires each Fiber it removes, so the live slots are exactly the Fibers reachable from
  /// the root. The root pass and the first render still walk the tree. Debug builds check the invariant against
  /// that walk here.
  private func noteStructuralArenaCurrent() {
    metrics.retainedStructuralNodes = structuralArena.liveCount
    #if DEBUG
    let reachable = collectStructuralIDs(root)
    assert(
      reachable.count == structuralArena.liveCount && reachable.allSatisfy { structuralArena.isLive($0) },
      "structural arena and Fiber tree disagree"
    )
    #endif
  }

  private func collectStructuralIDs(_ fiber: Fiber) -> [StructuralNodeID] {
    var result: [StructuralNodeID] = []
    var pending = [fiber]
    while let current = pending.popLast() {
      result.append(current.structuralID)
      pending.append(contentsOf: current.children)
    }
    return result
  }

  private func flushPendingAppear() {
    guard reconciliationDepth == 0, !disposed else { return }
    stateStore._flushAfterCommitEffects()
    while !pendingAppearNodes.isEmpty {
      let nodes = pendingAppearNodes
      pendingAppearNodes.removeAll(keepingCapacity: true)
      for node in nodes { invokeLifecycle(named: "appear", in: node) }
    }
  }

  private func invokeLifecycle(named name: String, in root: _RenderNode) {
    // A loop over an explicit stack, in the order of the recursion it replaces (a node, then its children in
    // order): a deep view hierarchy is a tree as deep, and a WebKit Worker's stack holds few WebAssembly frames.
    var pending = [root]
    while let node = pending.popLast() {
      if name == "appear", reconciliationDepth > 0 {
        pendingAppearNodes.append(node)
        continue
      }
      // Inactive TabView panels stay in the retained tree but are not part of
      // the currently presented UI. Do not let initial mount, parent teardown,
      // or a nested lifecycle pass start/cancel tasks owned by those panels.
      if isLifecycleHidden(node) || isClosedMenuPanel(node) { continue }
      if name == "disappear" {
        // `.task` has the same lifetime as the modified view.  Cancel before
        // invoking the user disappearance callback so an async task cannot
        // publish work into a subtree that is already leaving the graph.
        node.taskRegistrations.forEach { $0.cancel() }
      }
      node.events[name]?.action()
      if name == "appear" {
        node.taskRegistrations.forEach { $0.start() }
      }
      pending.append(contentsOf: node.children.reversed())
    }
  }

  package func findNode(withEvent name: String, in node: _RenderNode? = nil) -> _RenderNode? {
    var pending = [node ?? root.renderNode]
    while let candidate = pending.popLast() {
      if candidate.events[name] != nil { return candidate }
      pending.append(contentsOf: candidate.children.reversed())
    }
    return nil
  }

  private func makeChildren(of rootFiber: Fiber, node rootNode: _RenderNode) -> [Fiber] {
    // A loop over an explicit stack rather than a recursion, in the same order: a view hierarchy hundreds of levels
    // deep is a tree as deep, and a WebKit Worker's stack holds few WebAssembly frames.
    struct Frame {
      let fiber: Fiber
      let node: _RenderNode
      let keys: [_FiberKey]
      var next = 0
      var made: [Fiber] = []
    }
    var stack = [Frame(fiber: rootFiber, node: rootNode, keys: effectiveChildKeys(rootNode.children))]
    while true {
      let top = stack.count - 1
      let children = stack[top].node.children
      if stack[top].next < children.count {
        let offset = stack[top].next
        stack[top].next += 1
        let child = children[offset]
        let parent = stack[top].fiber
        let childFiber = Fiber(identity: parent.identity.child(stack[top].keys[offset]), node: child, parent: parent, stateStore: parent.stateStore, structuralID: structuralArena.allocate(), version: _epoch)
        metrics.structuralNodeAllocations += 1
        metrics.createdNodes += 1
        stack.append(Frame(fiber: childFiber, node: child, keys: effectiveChildKeys(child.children)))
      } else {
        let done = stack.removeLast()
        try! structuralArena.setChildren(of: done.fiber.structuralID, to: done.made.map { child in child.structuralID })
        if stack.isEmpty { return done.made }
        done.fiber.children = done.made
        refreshVolatility(done.fiber)
        stack[stack.count - 1].made.append(done.fiber)
      }
    }
  }

  /// Positional keys remain the fallback for genuinely unkeyed siblings.
  /// Only duplicate semantic keys receive an occurrence scope, preventing two
  /// live Fibers from sharing the same identity path.
  private func effectiveChildKeys(_ children: [_RenderNode]) -> [_FiberKey] {
    var occurrences: [_FiberKey: Int] = .init()
    return children.enumerated().map { offset, child in
      let semantic = child.key ?? _FiberKey(offset)
      let occurrence = occurrences[semantic, default: 0]
      occurrences[semantic] = occurrence + 1
      return _fiberKeyWithOccurrence(semantic, occurrence)
    }
  }

  private func stateScopePaths(in root: _RenderNode) -> Set<_FiberPath> {
    var paths = Set<_FiberPath>()
    var pending = [root]
    while let node = pending.popLast() {
      paths.formUnion(node._stateScopePaths)
      pending.append(contentsOf: node.children)
    }
    return paths
  }

  /// Returns deferred collections without evaluating any row body. The
  /// nearest element identity is used as the browser layout host; logical
  /// item ownership remains attached to the descriptor Fiber itself.
  package func _isStructuralNodeLive(_ id: StructuralNodeID) -> Bool {
    !disposed && structuralArena.isLive(id)
  }

  package func _lazyCollections() -> [_LazyCollectionInfo] {
    guard !disposed else { return [] }
    var result: [_LazyCollectionInfo] = []
    var pending: [(fiber: Fiber, nearestElement: FiberIdentity?)] = [(root, nil)]
    while let (fiber, nearestElement) = pending.popLast() {
      // Lazy collections make every ancestor volatile, so a clean subtree
      // cannot contain one.
      guard fiber === root || fiber.isVolatile else { continue }
      let nextElement: FiberIdentity?
      if case .element = fiber.renderNode.kind {
        nextElement = fiber.identity
      } else {
        nextElement = nearestElement
      }
      if let descriptor = fiber.renderNode.lazyCollection,
         let containerIdentity = nextElement {
        result.append(_LazyCollectionInfo(ownerIdentity: fiber.identity, containerIdentity: containerIdentity, descriptor: descriptor))
      }
      for child in fiber.children.reversed() { pending.append((child, nextElement)) }
    }
    return result
  }

  /// Re-renders rows materialized under an older revision of their collection against the current one, clamped to its
  /// count, so a publication never shows rows of the previous data (a filtered list that keeps the rows that no longer
  /// match until the host asks for the window). When the old window reached the end of the old data and the collection
  /// grew, the window extends to `growTo` rows (lanes times rows) so the new rows appear in the same publication.
  /// A window whose range and row keys are unchanged is rendered again as well: the collection was evaluated again
  /// because something its rows read changed (a selection, a favorite), and the host's next window request would find its
  /// rows "materialized from the current data" and keep them. Rows that compare their inputs and found them unchanged
  /// are reused, and what reconciles to the same nodes publishes nothing. Returns whether any collection was refreshed.
  @discardableResult package func _refreshStaleLazyWindows(growTo freshRows: (_LazyCollectionDescriptor) -> Int) -> Bool {
    var refreshed = false
    for info in _lazyCollections() {
      guard let owner = fiber(at: info.ownerIdentity), let window = owner._lazyWindow else { continue }
      let descriptor = info.descriptor
      guard window.revision != descriptor.revision else { continue }
      let lanes = max(1, descriptor.laneCount)
      let extent = descriptor.estimatedExtent
      let lower = min(window.lower, descriptor.count)
      var upper = min(descriptor.count, window.upper)
      if window.upper >= window.count, descriptor.count > window.count {
        // The host's row count comes from outside: an overflowing product or sum clamps to the collection's count.
        let (grownRows, rowsOverflow) = freshRows(descriptor).multipliedReportingOverflow(by: lanes)
        let (grownUpper, upperOverflow) = lower.addingReportingOverflow(grownRows)
        let target = rowsOverflow || upperOverflow ? descriptor.count : grownUpper
        upper = min(descriptor.count, max(upper, target))
      }
      let keys = (lower..<upper).map(descriptor.keyAt)
      let sameRows = lower == window.lower && upper == window.upper && keys == window.keys
      let before = lower == window.lower ? window.before : Double(lower / lanes) * extent
      // Rows that keep their keys keep the spacer the host sized from what it measured; their content is rendered again below.
      let after = sameRows ? spacerExtent(of: info.ownerIdentity, key: "__lazy_after", axis: descriptor.axis)
        : Double((max(0, descriptor.count - upper) + lanes - 1) / lanes) * extent
      _materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: Array(lower..<upper), beforeExtent: before, afterExtent: after)
      refreshed = true
    }
    return refreshed
  }

  /// The owner token of the nearest fiber above `fiber` that has one: the erased view whose body produced it.
  private func nearestOwnerToken(above fiber: Fiber) -> UInt64? {
    var current = fiber.parentIdentity.flatMap { self.fiber(at: $0) }
    while let candidate = current {
      if let token = candidate.renderOwnerToken { return token }
      current = candidate.parentIdentity.flatMap { self.fiber(at: $0) }
    }
    return nil
  }

  /// The extent of the spacer `key` of a lazy owner, as it was last published; the estimate when the owner has none.
  private func spacerExtent(of ownerIdentity: FiberIdentity, key: String, axis: _LazyAxis) -> Double {
    guard let owner = fiber(at: ownerIdentity), let spacer = owner.children.last(where: { $0.renderNode.attributes["data-lazy-spacer"] == key }),
          let size = spacer.renderNode.attributes[axis == .vertical ? "data-size-h" : "data-size-w"], let extent = Double(size) else { return 0 }
    return extent
  }

  /// Materializes one visible logical range under an existing ForEach owner.
  /// The browser can call this repeatedly while scrolling; keyed Fiber
  /// reconciliation preserves overlapping logical rows and lifecycle/state
  /// ownership, while off-screen rows are removed from the active DOM graph.
  @discardableResult package func _materializeLazyCollection(
    ownerIdentity: FiberIdentity,
    indices: [Int],
    beforeExtent: Double,
    afterExtent: Double
  ) -> [Mutation] {
    guard !disposed else { return [] }
    guard let owner = fiber(at: ownerIdentity), let descriptor = owner.renderNode.lazyCollection else { return [] }
    // Row bodies run here: a model they write (`lineLimit` set while a row's view model initializes) must only
    // mark the tree dirty. Without this the write re-enters a render pass from inside this one.
    defer { flushPendingAppear() }
    reconciliationDepth += 1
    stateStore._beginEffectDeferral()
    defer {
      reconciliationDepth -= 1
      stateStore._endEffectDeferral()
    }
    metrics.lazyMaterializations += 1
    // Children are replaced below, so the copy can adopt the old ones.
    let node = owner.renderNode.cloneSharingChildren()
    // The host asks for the window again after a publication materialized it (`_refreshStaleLazyWindows`), sized by the
    // rows it measured. When the window holds the rows already materialized from the current data, their nodes are kept
    // and only the spacers change: every row was rendered again to resize two spacers (a list filtering while typing).
    if let rows = materializedRows(of: owner, descriptor: descriptor, indices: indices) {
      let before = makeLazySpacer(axis: descriptor.axis, extent: beforeExtent, key: "__lazy_before", tag: descriptor.spacerTag, columnCount: descriptor.spacerColumnCount)
      let after = makeLazySpacer(axis: descriptor.axis, extent: afterExtent, key: "__lazy_after", tag: descriptor.spacerTag, columnCount: descriptor.spacerColumnCount)
      let spacers = (owner.children.first?.renderNode, owner.children.last?.renderNode)
      if spacers.0?.attributes == before.attributes, spacers.1?.attributes == after.attributes { return [] }
      owner._lazyWindow?.before = beforeExtent
      node.children = [before] + rows + [after]
      prepareStaticTemplates(in: node)
      sealedWritesAtRender = _RenderNode.sealedWrites
      noteRenderEnded()
      _lastPackedMutations.reset()
      _lastPackedMutations.setOwnerRoot(root)
      givenUpOwnerTokens = []
      reconcile(fiber: owner, newNode: node, parent: nil, index: 0, mutations: _lastPackedMutations)
      retireGivenUpOwnerTokens()
      noteStructuralArenaCurrent()
      let mutations = finalizePackedMutations(materialize: true)
      lastMutations = mutations
      return mutations
    }
    metrics.lazyLogicalRowsMaterialized += indices.count
    var children: [_RenderNode] = []
    children.append(makeLazySpacer(
      axis: descriptor.axis,
      extent: beforeExtent,
      key: "__lazy_before",
      tag: descriptor.spacerTag,
      columnCount: descriptor.spacerColumnCount
    ))
    var seen = Set<UInt64>()
    var provenLeafSources = Set<_StateSourceID>()
    let closureOwnerToken = nearestOwnerToken(above: owner)
    // Materialization replaces the visible logical window of this owner. Use
    // the same ownership replacement semantics as a targeted pass so removed
    // rows cannot leave stale owner tokens behind while the rest of the root
    // dependency graph remains intact.
    let replacingOwnerTokens = collectOwnerTokens(in: owner)
    stateStore._beginSubtreeRenderPass(replacing: replacingOwnerTokens)
    sealedWritesAtRender = _RenderNode.sealedWrites
    for index in indices where index >= 0 && index < descriptor.count {
      guard seen.insert(UInt64(index)).inserted else { continue }
      let key = descriptor.keyAt(index)
      var rowContext = _RenderContext(
        environment: environment,
        path: [],
        stateStore: stateStore,
        preferenceStore: preferenceStore,
        _layoutCacheStore: layoutCacheStore,
        _splitViewStateStore: splitViewStateStore
      )
      rowContext._fiberPath = owner.identity.fiberPath
      rowContext._renderOwnerRegistry = renderOwnerRegistry
      // What the item closure reads before a view of the row registers its own owner (a selection, a favorite) belongs to the
      // view that wrote the closure: without an owner such a change could only be answered by a pass over the whole tree, which
      // finds that view's inputs unchanged, reuses its render and leaves the rows as they were.
      rowContext._renderOwnerToken = closureOwnerToken ?? owner.renderOwnerToken
      let rendered = descriptor.renderItem(index, rowContext)
      metrics.bodyEvaluations += 1
      metrics.renderNodeAllocations += countRenderNodes(rendered)
      collectLeafSources(rendered, into: &provenLeafSources)
      let item = makeLazyCell(
        rendered,
        key: key,
        index: index,
        itemType: descriptor.itemType,
        ownerIdentity: owner.identity
      )
      children.append(item)
    }
    // Recorded whether or not rows changed: a later publication compares this window (its revision, range and row keys)
    // with the collection's current one to find rows rendered from data that has since changed.
    let lower = seen.min().map { Int($0) } ?? 0, upper = seen.max().map { Int($0) + 1 } ?? 0
    owner._lazyWindow = (descriptor.revision, lower, upper, descriptor.count, beforeExtent, (lower..<upper).map(descriptor.keyAt))
    stateStore._endSubtreeRenderPass(provenLeafSources: provenLeafSources)
    children.append(makeLazySpacer(
      axis: descriptor.axis,
      extent: afterExtent,
      key: "__lazy_after",
      tag: descriptor.spacerTag,
      columnCount: descriptor.spacerColumnCount
    ))
    noteRenderEnded()
    node.children = children
    prepareStaticTemplates(in: node)
    _lastPackedMutations.reset()
    _lastPackedMutations.setOwnerRoot(root)
    givenUpOwnerTokens = []
    reconcile(fiber: owner, newNode: node, parent: nil, index: 0, mutations: _lastPackedMutations)
    retireGivenUpOwnerTokens()
    // Only the lazy owner was reconciled: no walk of the whole tree (see `noteStructuralArenaCurrent`).
    noteStructuralArenaCurrent()
    bindingRuntime.sync(root: root)
    sampleRetainedMemory()
    stateStore._clearDirtySources()
    let mutations = finalizePackedMutations(materialize: true)
    lastMutations = mutations
    return mutations
  }

  /// The nodes of the rows `owner` holds when they are the rows `indices` names, materialized from the collection's
  /// current data (same revision and count, the same contiguous range, the window's spacers around them), and nothing
  /// is waiting to render (a request is also how a row whose object or own state changed renders again); else nil.
  private func materializedRows(of owner: Fiber, descriptor: _LazyCollectionDescriptor, indices: [Int]) -> [_RenderNode]? {
    guard !_hasPendingInvalidation, !stateStore._hasPendingObservationInvalidation(), !stateStore._hasDirtySourcesOtherThanEnvironment() else { return nil }
    guard let window = owner._lazyWindow, let lower = indices.first, window.revision == descriptor.revision,
          window.count == descriptor.count, window.lower == lower, window.upper == lower + indices.count,
          indices.elementsEqual(lower..<(lower + indices.count)), owner.children.count == indices.count + 2,
          owner.children.first?.renderNode.attributes["data-lazy-spacer"] == "__lazy_before",
          owner.children.last?.renderNode.attributes["data-lazy-spacer"] == "__lazy_after" else { return nil }
    return owner.children.dropFirst().dropLast().map { $0.renderNode }
  }

  private func makeLazySpacer(axis: _LazyAxis, extent: Double, key: String, tag: String = "div", columnCount: Int = 1) -> _RenderNode {
    let node = _RenderNode.element(tag)
    node.key = _FiberKey(key)
    node.classes = ["lazy-spacer"]
    node.attributes["data-lazy-spacer"] = key
    node.attributes["data-layout-kind"] = "size"
    node.attributes["data-size-w"] = String(axis == .horizontal ? max(0, extent) : 0)
    node.attributes["data-size-h"] = String(axis == .vertical ? max(0, extent) : 0)
    let value = "\(max(0, extent))px"
    if axis == .vertical { node.styles["height"] = value } else { node.styles["width"] = value }
    if tag.lowercased() == "tr" {
      let cell = _RenderNode.element("td")
      cell.attributes["colspan"] = String(max(1, columnCount))
      cell.styles["height"] = value
      cell.styles["padding"] = "0"
      cell.styles["border"] = "0"
      node.children = [cell]
    }
    return node
  }

  private func collectLeafSources(_ root: _RenderNode, into sources: inout Set<_StateSourceID>) {
    var pending = [root]
    while let node = pending.popLast() {
      for descriptor in node.leafBindings { sources.insert(descriptor.sourceID) }
      pending.append(contentsOf: node.children)
    }
  }

  private func makeLazyCell(
    _ rendered: _RenderNode,
    key: _FiberKey,
    index: Int,
    itemType: String,
    ownerIdentity: FiberIdentity
  ) -> _RenderNode {
    let node: _RenderNode
    switch rendered.kind {
    case .element:
      node = rendered
      node.key = key
    case .empty:
      node = _RenderNode.element("div")
      node.key = key
    default:
      // A wrapper is necessary for text/fragments so the browser can measure
      // and recycle one physical cell without changing the logical item key.
      node = _RenderNode.element("div")
      node.key = key
      node.children = [rendered]
    }
    node.classes.append("lazy-cell")
    node.attributes["data-lazy-cell"] = "true"
    node.attributes["data-lazy-index"] = String(index)
    node.attributes["data-lazy-type"] = itemType
    // Multiple independent ForEach descriptors may share one Lazy* container.
    // Keep the logical owner on every physical cell so measurement, observer
    // wiring and recycling never mix indexes from sibling collections.
    node.attributes["data-lazy-owner"] = ownerIdentity.fiberPath._compactID(in: stateStore._compactPathIDs)
    return node
  }

  /// A retained static representation may keep its original _RenderNode
  /// objects, but each render pass still receives fresh erased-view owner
  /// tokens.  Adopt those tokens recursively so StateStore subscriptions and
  /// future targeted invalidations continue to resolve to the live Fibers.
  private func adoptOwnerTokens(_ rootFiber: Fiber, from rootNode: _RenderNode) {
    var pending: [(fiber: Fiber, node: _RenderNode)] = [(rootFiber, rootNode)]
    while let (fiber, node) = pending.popLast() {
      refreshOwnerToken(node._renderOwnerToken, on: fiber)
      let nodeChildren = node.children
      for (index, child) in fiber.children.enumerated().reversed() where index < nodeChildren.count {
        pending.append((child, nodeChildren[index]))
      }
    }
  }

  private func reconcile(fiber: Fiber, newNode: _RenderNode, parent: Fiber?, index: Int, mutations: _PackedMutationBuffer) {
    // A subtree can be reconciled independently after an Observation update.
    // Seed its lifecycle visibility from the retained ancestors once, then
    // propagate it during the recursive pass instead of walking parent paths
    // for every node in a large tree.
    let lifecycleParent = parent ?? fiber.parentIdentity.flatMap { self.fiber(at: $0) }
    let parentVisible = lifecycleIsVisible(in: lifecycleParent)
    reconcile(
      fiber: fiber,
      newNode: newNode,
      parent: parent,
      index: index,
      mutations: mutations,
      oldParentVisible: parentVisible,
      newParentVisible: parentVisible,
      lifecycleSuppressed: false
    )
  }

  /// A fiber being reconciled: what is settled before its children are walked, and what the walk needs to finish.
  private struct ReconcileFrame {
    let fiber: Fiber
    let newNode: _RenderNode
    let oldVisible: Bool
    let newVisible: Bool
    let suppressChildLifecycle: Bool
    let visibilityChanged: Bool
    let ownChanged: Bool
    let oldChildren: [Fiber]
    let newEffectiveKeys: [_FiberKey]
    let plan: ChildPlan
    var childrenChanged: Bool
    var nextChildren: [Fiber]
    var newIndex = 0
  }

  /// A loop over an explicit stack rather than a recursion: a view hierarchy hundreds of levels deep is a tree as
  /// deep, and one WebAssembly frame per level of it (this function's frame is a large one) is more than a WebKit
  /// Worker's stack holds. A child's reconcile still runs where the recursion would have run it: after the work
  /// before the parent's child loop, between its children, and before the work after the loop.
  private func reconcile(
    fiber: Fiber,
    newNode: _RenderNode,
    parent: Fiber?,
    index: Int,
    mutations: _PackedMutationBuffer,
    oldParentVisible: Bool,
    newParentVisible: Bool,
    lifecycleSuppressed: Bool
  ) {
    var stack: [ReconcileFrame] = []
    if let frame = beginReconcile(
      fiber: fiber, newNode: newNode, mutations: mutations,
      oldParentVisible: oldParentVisible, newParentVisible: newParentVisible, lifecycleSuppressed: lifecycleSuppressed
    ) {
      stack.append(frame)
    }
    while !stack.isEmpty {
      let top = stack.count - 1
      guard stack[top].newIndex < stack[top].newNode.children.count else {
        let finished = stack.removeLast()
        finishReconcile(finished, mutations: mutations)
        if !stack.isEmpty { adoptReconciledChild(finished.fiber, into: &stack[stack.count - 1]) }
        continue
      }
      let newIndex = stack[top].newIndex
      stack[top].newIndex += 1
      var childNode = stack[top].newNode.children[newIndex]
      let oldIndex = stack[top].plan.oldIndices[newIndex]
      let parentFiber = stack[top].fiber
      if oldIndex != UInt32.max {
        let childFiber = stack[top].oldChildren[Int(oldIndex)]
        if Int(oldIndex) != newIndex {
          stack[top].childrenChanged = true
          if mutations.isRecording { mutations.appendMove(node: childNode, parent: parentFiber, from: Int(oldIndex), to: newIndex, targetID: childFiber.structuralID) }
          metrics.reconciliationOperations += 1
        }
        // A view kept what this fiber shows (`_RenderNode._retainedRender`, a hidden tab already built): the parent
        // holds the retained node, and nothing below is walked while its visibility stays the same. When it changed
        // (the tab that was selected is now hidden) the node is reconciled against itself, for its lifecycle.
        if childNode._retainsRenderedSubtree {
          childNode = childFiber.renderNode
          stack[top].newNode.children[newIndex] = childNode
          if stack[top].oldVisible == stack[top].newVisible && !stack[top].suppressChildLifecycle {
            metrics.equatableSubtreesReused += 1
            adoptReconciledChild(childFiber, into: &stack[top])
            continue
          }
        }
        // Typed descriptor comparison, .task and lifecycle closures remain in
        // Swift. The child plan decides which retained record is reused for this child.
        if let frame = beginReconcile(
          fiber: childFiber, newNode: childNode, mutations: mutations,
          oldParentVisible: stack[top].oldVisible, newParentVisible: stack[top].newVisible,
          lifecycleSuppressed: stack[top].suppressChildLifecycle
        ) {
          stack.append(frame)
        } else {
          adoptReconciledChild(childFiber, into: &stack[top])
        }
      } else {
        let key = stack[top].newEffectiveKeys[newIndex]
        let childFiber = Fiber(identity: parentFiber.identity.child(key), node: childNode, parent: parentFiber, stateStore: parentFiber.stateStore, structuralID: structuralArena.allocate(), version: _epoch)
        stack[top].childrenChanged = true
        metrics.structuralNodeAllocations += 1
        metrics.createdNodes += 1
        childFiber.children = makeChildren(of: childFiber, node: childNode)
        refreshVolatility(childFiber)
        indexSubtree(childFiber)
        if mutations.isRecording { mutations.appendInsert(node: childNode, parent: parentFiber, index: newIndex, targetID: childFiber.structuralID) }
        metrics.reconciliationOperations += 1
        if !stack[top].suppressChildLifecycle, stack[top].newVisible, !isLifecycleHidden(childNode), !isClosedMenuPanel(childNode) {
          invokeLifecycle(named: "appear", in: childNode)
        }
        stack[top].nextChildren.append(childFiber)
      }
    }
  }

  /// What follows a matched child's reconcile in its parent's child loop.
  private func adoptReconciledChild(_ childFiber: Fiber, into frame: inout ReconcileFrame) {
    childFiber.reparent(to: frame.fiber)
    if childFiber.version >= _epoch { frame.childrenChanged = true }
    metrics.retainedNodes += 1
    frame.nextChildren.append(childFiber)
  }

  /// The work of `reconcile` before it walks the children. Returns nil when the fiber needs no child walk.
  private func beginReconcile(
    fiber: Fiber,
    newNode: _RenderNode,
    mutations: _PackedMutationBuffer,
    oldParentVisible: Bool,
    newParentVisible: Bool,
    lifecycleSuppressed: Bool
  ) -> ReconcileFrame? {
    metrics.reconciledNodes += 1
    metrics.structuralNodeVisits += 1
    let oldNode = fiber.renderNode
    // An `EquatableView` hands back the very node it rendered last time. At an unchanged visibility nothing below
    // it can differ, so the subtree is not walked; only its own owner token can have moved with an enclosing owner.
    if newNode === oldNode && oldParentVisible == newParentVisible && !lifecycleSuppressed && !fiber.isVolatile
        && !renderWroteSealedNodes {
      refreshOwnerToken(newNode._renderOwnerToken, on: fiber)
      metrics.equatableSubtreesReused += 1
      return nil
    }
    if let previous = oldNode._domView, let next = newNode._domView {
      next.adoptState(from: previous)
    }
    let oldVisible = oldParentVisible && !isLifecycleHidden(oldNode) && !isClosedMenuPanel(oldNode)
    let newVisible = newParentVisible && !isLifecycleHidden(newNode) && !isClosedMenuPanel(newNode)
    let visibilityChanged = !lifecycleSuppressed && oldVisible != newVisible
    let suppressChildLifecycle = lifecycleSuppressed || visibilityChanged
    let domViewIdentityChanged: Bool
    switch (oldNode._domView, newNode._domView) {
    case let (old?, new?):
      domViewIdentityChanged = !old.hasSameType(as: new)
    case (nil, nil):
      domViewIdentityChanged = false
    default:
      domViewIdentityChanged = true
    }

    // TabView keeps inactive panels mounted to preserve their state. Their
    // lifecycle must nevertheless match visibility: cancel the outgoing
    // panel before reconciliation, and start the incoming panel only after
    // its retained subtree has been updated.
    if visibilityChanged, oldVisible {
      invokeLifecycle(named: "disappear", in: oldNode)
    }
    if oldNode.kind != newNode.kind || oldNode.key != newNode.key || oldNode.descriptor != newNode.descriptor || domViewIdentityChanged {
      if !suppressChildLifecycle, oldVisible {
        invokeLifecycle(named: "disappear", in: oldNode)
      }
      if mutations.isRecording { mutations.appendReplace(previous: oldNode, new: newNode, fiber: fiber) }
      metrics.reconciliationOperations += 1
      // A replacement can change the render representation while keeping the
      // same semantic state scope (for example a keyed AnyView row). Preserve
      // only the scope explicitly emitted by the new node. Descendant Fibers
      // are removed below and retire their own state independently.
      releasingStateScopes {
        releaseStateScopes(for: fiber, preservingStateScopes: Set(newNode._stateScopePaths))
        if let oldToken = fiber.renderOwnerToken, oldToken != newNode._renderOwnerToken {
          renderOwnerRegistry._remove(oldToken)
        }
        releaseChildren(of: fiber)
      }
      updateFiber(fiber, with: newNode)
      fiber.children = makeChildren(of: fiber, node: newNode)
      fiber.version = _epoch
      refreshVolatility(fiber)
      for child in fiber.children { indexSubtree(child) }
      if !suppressChildLifecycle, newVisible {
        invokeLifecycle(named: "appear", in: newNode)
      } else if visibilityChanged, newVisible {
        invokeLifecycle(named: "appear", in: newNode)
      }
      return nil
    }
    // A lazy descriptor is a structural placeholder. Root reevaluation must
    // not tear down its currently materialized window merely because the new
    // descriptor intentionally has no eager children; the browser layout pass
    // will reconcile that window against the latest collection next.
    if newNode.lazyCollection != nil, newNode.children.isEmpty, !oldNode.children.isEmpty {
      newNode.children = oldNode.children
    }
    // Static template hoisting is deliberately representation-only. Bodies
    // have already been evaluated, and the complete semantic fingerprint is
    // equal, so retaining the old _RenderNode graph is safe and avoids a
    // recursive reconciliation walk and DOM work. Lifecycle-bearing or
    // state-bound nodes never receive a static key and use the normal path.
    if let oldTemplate = oldNode._staticTemplateKey,
       oldTemplate == newNode._staticTemplateKey {
      adoptOwnerTokens(fiber, from: newNode)
      metrics.staticTemplateReuses += 1
      return nil
    }
    var ownChanged = false
    if !oldNode.shallowEquals(newNode) {
      ownChanged = true
      if mutations.isRecording { mutations.appendUpdate(previous: oldNode, new: newNode, fiber: fiber) }
      metrics.reconciliationOperations += 1
      metrics.relaidOutNodes += 1
      updateFiber(fiber, with: newNode)

      // SwiftUI's `.task(id:)` restarts when its Equatable ID changes even
      // though the surrounding Fiber keeps the same identity. Compare each
      // registration by its stable modifier key; StateStore cancels the old
      // operation before starting the replacement.
      let oldTasks = Dictionary(uniqueKeysWithValues: oldNode.taskRegistrations.map { ($0.key, $0.id) })
      for task in newNode.taskRegistrations {
        if oldTasks[task.key] != task.id,
           oldVisible,
           newVisible,
           !suppressChildLifecycle {
          task.start()
        }
      }
    }
    // Deferred collection closures capture the latest data/content value even
    // when the placeholder's visible semantic shape is unchanged. Refresh
    // the descriptor without forcing a replace of the owner Fiber.
    if oldNode.lazyCollection != nil || newNode.lazyCollection != nil {
      fiber.renderNode.lazyCollection = newNode.lazyCollection
    }
    // Drag/drop descriptors contain closures and therefore intentionally do
    // not participate in _RenderNode semantic equality. Keep the latest
    // descriptor on a retained Fiber so a state-driven source/target update
    // resolves the current action without forcing a DOM mutation.
    fiber.renderNode._dragSource = newNode._dragSource
    fiber.renderNode._dropTarget = newNode._dropTarget
    fiber.renderNode._timeline = newNode._timeline
    fiber.renderNode._domView = newNode._domView
    // Owner tokens can change without changing rendered semantics.
    refreshOwnerToken(newNode._renderOwnerToken, on: fiber)
    fiber.renderNode._stateScopePaths = newNode._stateScopePaths

    let oldChildren = fiber.children
    // Every child Fiber's identity ends with the effective key it was created or matched under, so the old
    // side needs no recomputation (hashing every key with its occurrence count again on every pass).
    let oldEffectiveKeys = oldChildren.map { $0.identity.fiberPath.last! }
    let newEffectiveKeys = effectiveChildKeys(newNode.children)
    // Full Swift Hashable equality (custom keys and the keyed/unkeyed positional policy) decides a match, never a
    // hash or a textual description.
    let plan = ChildPlan(old: oldEffectiveKeys, new: newEffectiveKeys)
    let childrenChanged = !plan.removals.isEmpty
    let activeStateScopePaths = plan.removals.isEmpty ? Set<_FiberPath>() : stateScopePaths(in: newNode)
    // The plan lists deterministic removals as well as matches. Retire their
    // generations before allocating insertions, but keep Swift's lifecycle
    // callbacks and emitted DOM ordering at their historical boundaries.
    // Their state scopes are released together, still before any insertion.
    releasingStateScopes {
      for oldIndex in plan.removals {
        let oldFiber = oldChildren[Int(oldIndex)]
        // A replacement may reuse a modifier's task scope. Retire the outgoing
        // lifecycle before inserting any replacement, otherwise its late
        // disappearance cancels the new task registered under that same scope.
        if !suppressChildLifecycle, oldVisible, !isLifecycleHidden(oldFiber.renderNode), !isClosedMenuPanel(oldFiber.renderNode) {
          invokeLifecycle(named: "disappear", in: oldFiber.renderNode)
        }
        var preservedStateScopePaths = activeStateScopePaths
        if let descriptor = newNode.lazyCollection,
           descriptor.containsKey(oldEffectiveKeys[Int(oldIndex)]) {
          preservedStateScopePaths.formUnion(stateScopePaths(in: oldFiber.renderNode))
        }
        releaseSubtree(
          oldFiber,
          preservingStateScopes: preservedStateScopePaths
        )
      }
    }
    var nextChildren: [Fiber] = []
    nextChildren.reserveCapacity(newNode.children.count)
    return ReconcileFrame(
      fiber: fiber,
      newNode: newNode,
      oldVisible: oldVisible,
      newVisible: newVisible,
      suppressChildLifecycle: suppressChildLifecycle,
      visibilityChanged: visibilityChanged,
      ownChanged: ownChanged,
      oldChildren: oldChildren,
      newEffectiveKeys: newEffectiveKeys,
      plan: plan,
      childrenChanged: childrenChanged,
      nextChildren: nextChildren
    )
  }

  /// The work of `reconcile` after it has walked the children.
  private func finishReconcile(_ frame: ReconcileFrame, mutations: _PackedMutationBuffer) {
    let fiber = frame.fiber
    let newNode = frame.newNode
    for oldIndex in frame.plan.removals {
      let oldFiber = frame.oldChildren[Int(oldIndex)]
      if mutations.isRecording { mutations.appendRemove(node: oldFiber.renderNode, parent: fiber, index: Int(oldIndex), targetID: oldFiber.structuralID) }
      metrics.reconciliationOperations += 1
    }
    fiber.children = frame.nextChildren
    try! structuralArena.setChildren(of: fiber.structuralID, to: frame.nextChildren.map { child in child.structuralID })
    // Child Fibers may have retained their old static _RenderNode instances;
    // keep the parent graph pointing at those retained representations rather
    // than replacing them with freshly evaluated candidates.
    fiber.renderNode.children = frame.nextChildren.map { child in child.renderNode }
    fiber.renderNode.events = newNode.events
    fiber.renderNode._staticTemplateKey = newNode._staticTemplateKey
    if frame.ownChanged || frame.childrenChanged { fiber.version = _epoch }
    refreshVolatility(fiber)

    if frame.visibilityChanged, frame.newVisible {
      invokeLifecycle(named: "appear", in: fiber.renderNode)
    }
  }

  private func isLifecycleHidden(_ node: _RenderNode) -> Bool {
    if node.attributes["data-tab-panel"] == "true",
       node.attributes["data-tab-hidden"] == "true" {
      return true
    }
    if node.attributes["data-navigation-inactive"] == "true" {
      return true
    }
    return node.classes.contains("navigation-root")
      && node.attributes["aria-hidden"] == "true"
  }

  /// The content of a Menu or context menu stays in the retained tree while the menu is closed; SwiftUI builds it
  /// only when the menu opens, so lifecycle callbacks inside it (which often start network requests) must not run
  /// for every row on mount. Unlike a hidden tab, its owners still render: the panel's DOM must stay current.
  private func isClosedMenuPanel(_ node: _RenderNode) -> Bool { node.attributes["role"] == "menu" }

  private func lifecycleIsVisible(in fiber: Fiber?) -> Bool {
    var current = fiber
    while let node = current {
      if isLifecycleHidden(node.renderNode) { return false }
      current = node.parentIdentity.flatMap { self.fiber(at: $0) }
    }
    return true
  }
}
