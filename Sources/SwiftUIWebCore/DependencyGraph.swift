// Which owners read which sources, and which of those changed. The contract is Documentation/OBSERVATION_CONTRACT.md.
// Sources are `_StateSourceID`s and owners are erased-view tokens; no model value, closure or object enters the graph.

/// What a dirty set asks the renderer to re-evaluate. `root` is a first-class result: shared or unowned sources are
/// correct only when the retained tree is reconciled from its root.
@_spi(Renderer) public enum _InvalidationPlan: Sendable, Equatable {
  case none
  case subtree([UInt64])
  case root
}

/// A point-in-time, typed view of the graph's dirty state, for instrumentation and contract tests.
@_spi(Renderer) public struct _DependencyDiagnostics: Sendable, Equatable {
  public let hasDirtyStructural: Bool
  public let hasObservation: Bool
  /// `nil` means at least one dirty structural source is shared or unowned and
  /// therefore requires the root fallback. An empty array means no applicable
  /// owner was selected for the current dirty set.
  public let uniqueStructuralOwners: [UInt64]?
  public let observationOwners: [UInt64]

  public init(
    hasDirtyStructural: Bool,
    hasObservation: Bool,
    uniqueStructuralOwners: [UInt64]?,
    observationOwners: [UInt64]
  ) {
    self.hasDirtyStructural = hasDirtyStructural
    self.hasObservation = hasObservation
    self.uniqueStructuralOwners = uniqueStructuralOwners
    self.observationOwners = observationOwners
  }

  public var structuralPlan: _InvalidationPlan {
    guard hasDirtyStructural else { return .none }
    guard let owners = uniqueStructuralOwners, !owners.isEmpty else { return .root }
    return .subtree(owners)
  }

  public var plan: _InvalidationPlan {
    switch structuralPlan {
    case .none:
      guard hasObservation else { return .none }
      return observationOwners.isEmpty ? .root : .subtree(observationOwners)
    case .subtree(let owners):
      // Structural ownership is the conservative authority. Observation
      // owners are supplemental and are unioned only when a structural plan
      // is already targetable.
      let combined = Set(owners).union(observationOwners).sorted()
      return combined.isEmpty ? .root : .subtree(combined)
    case .root:
      return .root
    }
  }
}

/// The dependency graph of one `StateStore`. A render pass records into pending state; `endPass` publishes it to the
/// committed graph the dirty queries read, so invalidation never sees a half-published ownership graph. Not
/// Sendable: callers serialize evaluation, mutation and disposal.
@_spi(Renderer) public final class _DependencyGraph {
  /// A root pass replaces the whole graph, a supplemental pass adds to it, and a subtree pass replaces the edges of
  /// the owners it re-evaluated.
  public enum PassMode: Sendable { case root, supplemental, subtree }

  private struct Pass {
    let mode: PassMode
    let replaced: Set<UInt64>
    /// Sources read without a leaf credit left to cover the read.
    var unproven: Set<_StateSourceID> = []
    /// Leaf reads still covered per source; a key stays after its credits are spent, because an unproven leaf is structural.
    var credits: [_StateSourceID: UInt32] = .init()
    var owners: [_StateSourceID: Set<UInt64>] = .init()
    var readers: Set<UInt64> = []
    /// Owners whose committed edges the pass keeps: a subtree the render reused without running its bodies read
    /// nothing in this pass, and still depends on what it read when it last ran.
    var kept: Set<UInt64> = []
  }

  private var structural: Set<_StateSourceID> = []
  private var observationSources: Set<_StateSourceID> = []
  /// `source -> owners`, the committed graph the dirty queries read.
  private var owners: [_StateSourceID: Set<UInt64>] = .init()
  /// `owner -> sources`, the inverse of `owners`: replacing an owner retires its edges without scanning every source.
  private var byOwner: [UInt64: Set<_StateSourceID>] = .init()
  private var dirty: Set<_StateSourceID> = []
  private var explicit: Set<_StateSourceID> = []
  private var pass: Pass?

  /// Number of committed `source -> owner` edges.
  public private(set) var edgeCount = 0
  /// Owners an `@Observable` change marked, whatever they read.
  public private(set) var observationOwners: Set<UInt64> = []

  public init() {}

  // MARK: Recording

  /// A pass is a serialized transaction: a second begin would discard the reads of the first.
  public func beginPass(_ mode: PassMode, replacing owners: Set<UInt64> = []) {
    precondition(pass == nil, "Dependency pass already in progress")
    pass = Pass(mode: mode, replaced: owners)
  }

  /// A read outside a pass (an event handler) does not subscribe.
  public func recordRead(_ source: _StateSourceID, owner: UInt64?) {
    guard pass != nil else { return }
    recordOwner(source, owner)
    if let credit = pass!.credits[source], credit > 0 {
      pass!.credits[source] = credit - 1
    } else {
      pass!.unproven.insert(source)
    }
  }

  /// A property-level read of a lowered `@Observable` member; it shares the owner graph with State reads, and its
  /// source is excluded from the structural State queries.
  public func observationAccess(_ source: _StateSourceID, owner: UInt64?) {
    observationSources.insert(source)
    recordRead(source, owner: owner)
  }

  /// The next read of `source` is a binding-backed leaf: structural unless the pass proves it.
  public func creditLeaf(_ source: _StateSourceID) {
    pass?.credits[source, default: 0] &+= 1
  }

  /// An aggregate source (a model's `objectWillChange`): always structural, never covered by a leaf credit.
  public func observeAggregate(_ source: _StateSourceID, owner: UInt64?) {
    explicit.insert(source)
    recordOwner(source, owner)
  }

  private func recordOwner(_ source: _StateSourceID, _ owner: UInt64?) {
    // Zero is the explicit "no owner" sentinel.
    guard pass != nil, let owner, owner != 0 else { return }
    pass!.owners[source, default: []].insert(owner)
    pass!.readers.insert(owner)
  }

  /// Keeps `owners`' committed edges through the current pass.
  public func keepOwners(_ owners: [UInt64]) {
    pass?.kept.formUnion(owners)
  }

  public func ownerReadInPass(_ owner: UInt64) -> Bool {
    pass?.readers.contains(owner) ?? false
  }

  /// Publishes the pass. A source is structural when a read was not covered by a proven leaf credit, a credit was not
  /// proven, or it is an aggregate; a root pass replaces the structural set and the edges, a subtree pass retires the
  /// edges of the owners it replaced (and the sources left without an owner stop being structural unless aggregate).
  public func endPass(provenLeafSources proven: Set<_StateSourceID>) {
    guard let pass else { return }
    self.pass = nil
    var classified = pass.unproven.union(explicit)
    for source in pass.credits.keys where !proven.contains(source) { classified.insert(source) }
    var keptEdges: [(source: _StateSourceID, owner: UInt64)] = []
    switch pass.mode {
    case .root:
      for owner in pass.kept {
        for source in byOwner[owner] ?? [] {
          keptEdges.append((source, owner))
          if structural.contains(source) { classified.insert(source) }
        }
      }
      structural.removeAll(keepingCapacity: true)
      owners.removeAll(keepingCapacity: true)
      byOwner.removeAll(keepingCapacity: true)
      edgeCount = 0
    case .subtree:
      for owner in pass.replaced where !pass.kept.contains(owner) { retire(owner) }
    case .supplemental:
      break
    }
    structural.formUnion(classified)
    for (source, sourceOwners) in pass.owners {
      for owner in sourceOwners { insertEdge(source, owner) }
    }
    for (source, owner) in keptEdges { insertEdge(source, owner) }
  }

  private func insertEdge(_ source: _StateSourceID, _ owner: UInt64) {
    guard owners[source, default: []].insert(owner).inserted else { return }
    byOwner[owner, default: []].insert(source)
    edgeCount += 1
  }

  /// Drops every edge the owner holds. A source left without owners loses its entry and, unless it is an
  /// aggregate, its structural classification.
  private func retire(_ owner: UInt64) {
    guard let sources = byOwner.removeValue(forKey: owner) else { return }
    for source in sources {
      if owners[source]?.remove(owner) != nil { edgeCount -= 1 }
      if owners[source]?.isEmpty == true {
        owners[source] = nil
        if !explicit.contains(source) { structural.remove(source) }
      }
    }
  }

  // MARK: Changes

  public func markDirty(_ source: _StateSourceID) { dirty.insert(source) }
  public func markObservation(_ owner: UInt64) { observationOwners.insert(owner) }
  public func clearObservation() { observationOwners.removeAll() }
  public func clearDirty() {
    dirty.removeAll()
    observationOwners.removeAll()
  }

  /// Drops every committed and pending dependency. The disposal boundary of a `StateStore`.
  public func reset() {
    structural.removeAll()
    observationSources.removeAll()
    owners.removeAll()
    byOwner.removeAll()
    edgeCount = 0
    dirty.removeAll()
    observationOwners.removeAll()
    explicit.removeAll()
    pass = nil
  }

  // MARK: Queries

  public func isStructural(_ source: _StateSourceID) -> Bool { structural.contains(source) }
  public var hasObservation: Bool { !observationOwners.isEmpty }
  public var hasDirtyStructural: Bool { !dirty.isDisjoint(with: structural) }
  public func hasDirtyOtherThan(_ source: _StateSourceID) -> Bool { dirty.contains { $0 != source } }

  /// Whether `owner` read a source that changed since the last pass, or an observation marked it: its body has to
  /// run again, so what it rendered cannot be reused.
  public func ownerIsDirty(_ owner: UInt64) -> Bool {
    observationOwners.contains(owner) || byOwner[owner].map { !dirty.isDisjoint(with: $0) } ?? false
  }

  /// The owner of every dirty structural source. `nil` is the root fallback: a source with no owner or with several
  /// is shared or unknown. `includingObservations: false` leaves out lowered `@Observable` member sources, which
  /// are fanned out by source through `dirtyOwners(of:)`.
  public func dirtyStructuralOwners(includingObservations: Bool = true) -> Set<UInt64>? {
    var result: Set<UInt64> = []
    for source in dirty where structural.contains(source) && (includingObservations || !observationSources.contains(source)) {
      guard let sourceOwners = owners[source], sourceOwners.count == 1 else { return nil }
      result.formUnion(sourceOwners)
    }
    return result
  }

  /// Every owner of `source` when it is dirty and structural (empty otherwise); `nil` when it has none.
  public func dirtyOwners(of source: _StateSourceID) -> Set<UInt64>? {
    guard dirty.contains(source), structural.contains(source) else { return [] }
    guard let sourceOwners = owners[source], !sourceOwners.isEmpty else { return nil }
    return sourceOwners
  }

  public var diagnostics: _DependencyDiagnostics {
    _DependencyDiagnostics(
      hasDirtyStructural: hasDirtyStructural,
      hasObservation: hasObservation,
      uniqueStructuralOwners: dirtyStructuralOwners()?.sorted(),
      observationOwners: observationOwners.sorted()
    )
  }
}
