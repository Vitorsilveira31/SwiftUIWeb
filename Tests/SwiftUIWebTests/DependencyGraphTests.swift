import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// The dependency graph's transaction semantics (Documentation/OBSERVATION_CONTRACT.md): pending versus committed
/// edges, structural classification, owner replacement and the root fallback.
@Suite struct DependencyGraphTests {
  private func id(_ value: UInt64) -> _StateSourceID { _StateSourceID(rawValue: value) }

  /// Runs one pass in which every pair is read once. Sources in `leaves` are read through a leaf credit and
  /// proven; a pair without an owner reads the source with none.
  private func commit(
    _ graph: _DependencyGraph, _ mode: _DependencyGraph.PassMode = .root, reads: [(UInt64, UInt64?)],
    leaves: Set<UInt64> = [], replacing: Set<UInt64> = []
  ) {
    graph.beginPass(mode, replacing: replacing)
    for (source, owner) in reads {
      if leaves.contains(source) { graph.creditLeaf(id(source)) }
      graph.recordRead(id(source), owner: owner)
    }
    graph.endPass(provenLeafSources: Set(leaves.map(id)))
  }

  private func owners(_ graph: _DependencyGraph) -> Set<UInt64>? { graph.dirtyStructuralOwners() }

  @Test func unreadWritesDoNotSelectOwners() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10), (2, 20)])
    graph.markDirty(id(1))
    #expect(owners(graph) == [10])
    graph.markDirty(id(99))
    #expect(owners(graph) == [10])
    graph.clearDirty()
    #expect(!graph.hasDirtyStructural)
  }

  @Test func subtreePassReplacesOnlyItsOwnersEdges() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10), (2, 20)])
    commit(graph, .subtree, reads: [(3, 10)], replacing: [10])
    #expect(!graph.isStructural(id(1)))
    #expect(graph.isStructural(id(2)))
    #expect(graph.edgeCount == 2)
    graph.markDirty(id(1))
    #expect(owners(graph) == [])
    graph.markDirty(id(3))
    #expect(owners(graph) == [10])
  }

  @Test func sharedSourcesFallBackToTheRootButFanOutBySource() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10), (1, 20)])
    graph.markDirty(id(1))
    #expect(owners(graph) == nil)
    #expect(graph.dirtyOwners(of: id(1)) == [10, 20])
  }

  @Test func dirtinessQueriesDistinguishEmptyStructuralAndUnrelatedSources() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10)])
    #expect(!graph.hasDirtyStructural)
    #expect(!graph.hasDirtyOtherThan(id(1)))

    graph.markDirty(id(2))
    #expect(!graph.hasDirtyStructural)
    #expect(graph.hasDirtyOtherThan(id(1)))
    #expect(graph.dirtyStructuralOwners(includingObservations: false) == [])

    graph.markDirty(id(1))
    #expect(graph.hasDirtyStructural)
    #expect(graph.dirtyStructuralOwners(includingObservations: false) == [10])
    graph.clearDirty()
    #expect(!graph.hasDirtyStructural)
    #expect(!graph.hasDirtyOtherThan(id(1)))
  }

  @Test func stateOwnersFallBackToTheRootForSharedOrUnownedSources() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10), (1, 20), (2, nil)])
    graph.markDirty(id(1))
    #expect(graph.dirtyStructuralOwners(includingObservations: false) == nil)

    graph.clearDirty()
    commit(graph, reads: [(2, nil)])
    graph.markDirty(id(2))
    #expect(graph.dirtyStructuralOwners(includingObservations: false) == nil)
  }

  @Test func aggregateAndUnownedSourcesStayConservative() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10)])
    graph.beginPass(.subtree, replacing: [10])
    graph.observeAggregate(id(1), owner: nil)
    graph.endPass(provenLeafSources: [])
    graph.markDirty(id(1))
    #expect(graph.isStructural(id(1)))
    #expect(owners(graph) == nil)
  }

  @Test func supplementalEdgesAndObservationOwnersCoalesce() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10)])
    commit(graph, .supplemental, reads: [(2, 20)])
    #expect(graph.edgeCount == 2)
    graph.markObservation(10)
    graph.markObservation(10)
    #expect(graph.observationOwners == [10])
    #expect(graph.hasObservation)
    graph.clearDirty()
    #expect(!graph.hasObservation)
  }

  @Test func clearObservationLeavesDirtySourcesAlone() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10)])
    graph.markDirty(id(1))
    graph.markObservation(10)
    graph.clearObservation()
    #expect(!graph.hasObservation)
    #expect(graph.hasDirtyStructural)
  }

  @Test func propertyObservationSharesTheOwnerGraph() {
    let graph = _DependencyGraph()
    graph.beginPass(.root)
    graph.observationAccess(id(41), owner: 7)
    graph.observationAccess(id(41), owner: 8)
    graph.recordRead(id(42), owner: 9)
    graph.endPass(provenLeafSources: [])
    graph.markDirty(id(41))
    graph.markDirty(id(42))
    // The all-sources query stays conservative for a source shared by several owners, while the observation source
    // fans out because its property-level read graph identifies every consumer.
    #expect(owners(graph) == nil)
    #expect(graph.dirtyOwners(of: id(41)) == [7, 8])
    #expect(graph.dirtyStructuralOwners(includingObservations: false) == [9])
  }

  @Test func unownedSourcesRequireTheRootFallback() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(41, nil)])
    graph.markDirty(id(41))
    #expect(owners(graph) == nil)
    #expect(graph.dirtyOwners(of: id(41)) == nil)
    #expect(graph.dirtyOwners(of: id(99)) == [])
  }

  @Test func passClassificationIsOwnedByTheGraph() {
    let graph = _DependencyGraph()
    graph.recordRead(id(99), owner: 10)  // an event read outside evaluation does not subscribe
    #expect(!graph.ownerReadInPass(10))
    graph.beginPass(.root)
    graph.recordRead(id(1), owner: 10)
    graph.creditLeaf(id(2))
    graph.recordRead(id(2), owner: 20)
    graph.creditLeaf(id(3))
    graph.recordRead(id(3), owner: 30)  // no proof for this leaf
    #expect(graph.ownerReadInPass(10))
    graph.endPass(provenLeafSources: [id(2)])
    #expect(graph.isStructural(id(1)))
    #expect(!graph.isStructural(id(2)))
    #expect(graph.isStructural(id(3)))
    #expect(!graph.isStructural(id(99)))
    #expect(!graph.ownerReadInPass(10))
    #expect(graph.edgeCount == 3)
  }

  @Test func aRawReadOverridesAProvenLeaf() {
    let graph = _DependencyGraph()
    graph.beginPass(.root)
    graph.creditLeaf(id(1))
    graph.recordRead(id(1), owner: 10)
    graph.recordRead(id(1), owner: 10)
    graph.endPass(provenLeafSources: [id(1)])
    #expect(graph.isStructural(id(1)))
  }

  @Test func conditionalPassReplacesOnlyTheTargetedOwner() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10), (2, 20)])
    commit(graph, .subtree, reads: [(3, 10)], replacing: [10])
    #expect(!graph.isStructural(id(1)))
    #expect(graph.isStructural(id(2)))
    graph.markDirty(id(3))
    #expect(owners(graph) == [10])
  }

  @Test func supplementalPassAndAggregatesKeepTheirContract() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10)])
    graph.observeAggregate(id(7), owner: nil)
    graph.beginPass(.supplemental)
    graph.observeAggregate(id(7), owner: 70)
    graph.endPass(provenLeafSources: [])
    #expect(graph.isStructural(id(1)))
    #expect(graph.isStructural(id(7)))
    commit(graph, .subtree, reads: [], replacing: [70])
    #expect(graph.isStructural(id(7)))
    graph.markDirty(id(7))
    #expect(owners(graph) == nil)
  }

  @Test func endingAPassTwiceKeepsTheCommittedGraph() {
    let graph = _DependencyGraph()
    graph.beginPass(.root)
    graph.recordRead(id(1), owner: 10)
    graph.endPass(provenLeafSources: [])
    graph.endPass(provenLeafSources: [])
    #expect(graph.isStructural(id(1)))
    #expect(graph.edgeCount == 1)
  }

  @Test func resetRetiresCommittedAndPendingState() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10)])
    graph.markDirty(id(1))
    graph.markObservation(10)
    graph.observationAccess(id(5), owner: 10)
    graph.beginPass(.root)
    graph.recordRead(id(2), owner: 20)
    graph.reset()
    #expect(graph.edgeCount == 0)
    #expect(!graph.hasDirtyStructural)
    #expect(!graph.hasObservation)
    #expect(owners(graph) == [])
    graph.endPass(provenLeafSources: [])
    #expect(!graph.isStructural(id(2)))
    graph.beginPass(.root)  // the pending pass is gone, so a new one may start
    graph.endPass(provenLeafSources: [])
  }

  @Test func replacingOwnersRetiresOnlyTheirEdges() {
    let graph = _DependencyGraph()
    // Source 1 is shared by owners 10 and 20; 2 belongs to 10 alone; 3 to 30.
    commit(graph, reads: [(1, 10), (1, 20), (2, 10), (3, 30)])
    #expect(graph.edgeCount == 4)
    commit(graph, .subtree, reads: [(4, 11)], replacing: [10])
    // Owner 10 is gone: 1 keeps owner 20, 2 lost its only owner, 3 and the new edge are untouched.
    #expect(graph.edgeCount == 3)
    #expect(graph.isStructural(id(1)))
    #expect(!graph.isStructural(id(2)))
    #expect(graph.isStructural(id(3)))
    #expect(graph.isStructural(id(4)))
    graph.markDirty(id(1))
    #expect(graph.dirtyOwners(of: id(1)) == [20])
    graph.markDirty(id(3))
    graph.markDirty(id(4))
    // Every dirty structural source now has exactly one owner.
    #expect(owners(graph) == [11, 20, 30])
    graph.clearDirty()
    graph.markDirty(id(2))
    #expect(graph.dirtyOwners(of: id(2)) == [])
    // Replacing an owner the graph never saw is a no-op.
    commit(graph, .subtree, reads: [], replacing: [99])
    #expect(graph.edgeCount == 3)
    // Re-adding an edge counts once, and the owner can be retired again.
    commit(graph, .supplemental, reads: [(1, 20), (1, 20), (2, 10)])
    #expect(graph.edgeCount == 4)
    commit(graph, .subtree, reads: [], replacing: [20, 10])
    // Only (3, 30) and (4, 11) remain.
    #expect(graph.edgeCount == 2)
    #expect(!graph.isStructural(id(1)))
    #expect(!graph.isStructural(id(2)))
    #expect(graph.isStructural(id(3)))
    #expect(graph.isStructural(id(4)))
  }

  @Test func aggregateSourcesStayStructuralWithoutOwners() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10), (2, 20)])
    graph.observeAggregate(id(2), owner: nil)
    commit(graph, .subtree, reads: [], replacing: [10, 20])
    #expect(!graph.isStructural(id(1)))
    #expect(graph.isStructural(id(2)))
    #expect(graph.edgeCount == 0)
    graph.markDirty(id(2))
    #expect(graph.dirtyOwners(of: id(2)) == nil)
  }

  @Test func ownerZeroAndReadsOutsideAPassDoNotSubscribe() {
    let graph = _DependencyGraph()
    graph.recordRead(id(1), owner: 0)
    graph.recordRead(id(1), owner: nil)
    graph.creditLeaf(id(1))
    #expect(!graph.ownerReadInPass(0))

    graph.beginPass(.root)
    graph.creditLeaf(id(2))
    graph.recordRead(id(2), owner: 0)
    graph.recordRead(id(2), owner: 0)  // the credit is spent, so the source is read raw
    #expect(!graph.ownerReadInPass(0))
    #expect(!graph.ownerReadInPass(99))
    graph.endPass(provenLeafSources: [id(2)])

    #expect(graph.isStructural(id(2)))
    graph.markDirty(id(2))
    #expect(graph.dirtyOwners(of: id(2)) == nil)
  }

  @Test func keptOwnersKeepTheirEdgesThroughARootAndASubtreePass() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 10), (2, 20)])
    // A root pass in which owner 20 was reused: it read nothing, and still depends on source 2.
    graph.beginPass(.root)
    graph.recordRead(id(1), owner: 10)
    graph.keepOwners([20])
    graph.endPass(provenLeafSources: [])
    #expect(graph.isStructural(id(2)))
    graph.markDirty(id(2))
    #expect(graph.dirtyOwners(of: id(2)) == [20])
    #expect(graph.ownerIsDirty(20))
    #expect(!graph.ownerIsDirty(10))
    graph.clearDirty()
    // A subtree pass replacing both owners, with 20 reused again: 10's edges are replaced, 20's stay.
    graph.beginPass(.subtree, replacing: [10, 20])
    graph.recordRead(id(3), owner: 10)
    graph.keepOwners([20])
    graph.endPass(provenLeafSources: [])
    graph.markDirty(id(2))
    #expect(graph.dirtyOwners(of: id(2)) == [20])
    graph.clearDirty()
    graph.markDirty(id(1))
    #expect(!graph.ownerIsDirty(10), "10 no longer reads source 1")
    // Without keeping it, a subtree pass retires the owner's edges.
    graph.clearDirty()
    commit(graph, .subtree, reads: [], replacing: [20])
    graph.markDirty(id(2))
    #expect(!graph.ownerIsDirty(20))
  }

  @Test func observationMarksMakeAnOwnerDirty() {
    let graph = _DependencyGraph()
    #expect(!graph.ownerIsDirty(10))
    graph.markObservation(10)
    #expect(graph.ownerIsDirty(10))
  }

  @Test func diagnosticsClassifySubtreeAndRootFallback() {
    let graph = _DependencyGraph()
    commit(graph, reads: [(1, 42)])
    graph.markDirty(id(1))
    #expect(graph.diagnostics.structuralPlan == .subtree([42]))
    #expect(graph.diagnostics.plan == .subtree([42]))

    graph.clearDirty()
    commit(graph, reads: [(2, 7), (2, 8)])
    graph.markDirty(id(2))
    #expect(graph.diagnostics.uniqueStructuralOwners == nil)
    #expect(graph.diagnostics.structuralPlan == .root)
    #expect(graph.diagnostics.plan == .root)

    graph.clearDirty()
    graph.markObservation(99)
    #expect(graph.diagnostics.plan == .subtree([99]))
  }

  // MARK: Property-style checks against an independent model

  private struct Generator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return state
    }
  }

  /// Commits `structural` sources and `edges` as a root pass. A non-structural edge source is read through a proven
  /// leaf credit, which is how the renderer produces an owned source that is not structural.
  private func commitModel(_ graph: _DependencyGraph, structural: Set<UInt64>, edges: [(UInt64, UInt64)]) {
    let leaves = Set(edges.map(\.0)).subtracting(structural)
    var reads: [(UInt64, UInt64?)] = structural.sorted().map { ($0, nil) }
    reads += edges.map { ($0.0, Optional($0.1)) }
    commit(graph, reads: reads, leaves: leaves)
  }

  @Test func deterministicFuzzPreservesTheInvalidationContract() {
    for seed in 0..<256 as Range<UInt64> {
      var random = Generator(state: seed ^ 0x9e37_79b9_7f4a_7c15)
      let graph = _DependencyGraph()
      for step in 0..<48 {
        var structural: Set<UInt64> = []
        var edges: [(UInt64, UInt64)] = []
        var owners: [UInt64: Set<UInt64>] = [:]
        for source in 1...12 as ClosedRange<UInt64> {
          // Force a semantically complete seed: a structural source without an owner, a shared source and a
          // uniquely owned one exercise distinct invalidation outcomes.
          if seed == 0 && step <= 2 {
            let seeded: (isStructural: Bool, owners: [UInt64])
            switch (step, source) {
            case (0, 1): seeded = (true, [])
            case (0, 2): seeded = (true, [10, 20])
            case (0, 3): seeded = (true, [30])
            case (1, 1...3): seeded = (true, [10])
            case (2, 2): seeded = (true, [10, 20])
            default: seeded = (false, [])
            }
            if seeded.isStructural { structural.insert(source) }
            for owner in seeded.owners {
              owners[source, default: []].insert(owner)
              edges.append((source, owner))
            }
            continue
          }
          if random.next() & 1 == 0 { structural.insert(source) }
          for _ in 0..<Int(random.next() % 4) {
            let owner = 1 + random.next() % 8
            owners[source, default: []].insert(owner)
            edges.append((source, owner))
          }
        }
        commitModel(graph, structural: structural, edges: edges)

        var dirty: Set<UInt64> = []
        for source in 1...16 as ClosedRange<UInt64> {
          let forced = seed == 0 && (step == 0 && source <= 3 || step == 1 && source <= 3 || step == 2 && source == 2)
          if forced || random.next() & 1 == 0 {
            graph.markDirty(id(source))
            dirty.insert(source)
          }
        }

        let structuralDirty = dirty.filter(structural.contains)
        let requiresRoot = structuralDirty.contains { (owners[$0]?.count ?? 0) != 1 }
        let expectedUnique = Set(structuralDirty.compactMap { owners[$0] }.filter { $0.count == 1 }.flatMap { $0 })
        if let actual = graph.dirtyStructuralOwners() {
          #expect(!requiresRoot)
          #expect(actual == expectedUnique)
        } else {
          #expect(requiresRoot)
        }

        for source in 1...16 as ClosedRange<UInt64> {
          let expected: Set<UInt64>?
          if !dirty.contains(source) || !structural.contains(source) {
            expected = []
          } else if let sourceOwners = owners[source], !sourceOwners.isEmpty {
            expected = sourceOwners
          } else {
            expected = nil
          }
          #expect(graph.dirtyOwners(of: id(source)) == expected)
        }
        graph.clearDirty()
      }
    }
  }

  @Test func reverseIndexStaysConsistentUnderRandomReplacement() {
    var random = Generator(state: 0x5eed)
    let graph = _DependencyGraph()
    // An independent model of the committed graph; source 5 is an aggregate, structural after every pass.
    var model: [UInt64: Set<UInt64>] = [:]
    var structural: Set<UInt64> = []
    graph.observeAggregate(id(5), owner: nil)
    for _ in 0..<400 {
      let mode = random.next() % 3
      var edges: [(UInt64, UInt64)] = []
      var listed: Set<UInt64> = []
      for _ in 0..<Int(random.next() % 6) {
        let source = 1 + random.next() % 9
        edges.append((source, 1 + random.next() % 7))
        if random.next() & 1 == 0 { listed.insert(source) }
      }
      let replaced = Set((0..<Int(random.next() % 3)).map { _ in 1 + random.next() % 7 })
      let leaves = Set(edges.map(\.0)).subtracting(listed)
      let passMode: _DependencyGraph.PassMode = mode == 0 ? .root : mode == 1 ? .supplemental : .subtree
      graph.beginPass(passMode, replacing: replaced)
      for source in listed.sorted() { graph.recordRead(id(source), owner: nil) }
      for (source, owner) in edges {
        if leaves.contains(source) { graph.creditLeaf(id(source)) }
        graph.recordRead(id(source), owner: owner)
      }
      graph.endPass(provenLeafSources: Set(leaves.map(id)))

      if mode == 0 {
        model.removeAll()
        structural.removeAll()
      }
      if mode == 2 {
        for source in Array(model.keys) {
          let before = model[source]!.count
          model[source]!.subtract(replaced)
          if before != model[source]!.count && model[source]!.isEmpty {
            model[source] = nil
            if source != 5 { structural.remove(source) }
          }
        }
      }
      structural.formUnion(listed)
      structural.insert(5)
      for (source, owner) in edges { model[source, default: []].insert(owner) }

      #expect(graph.edgeCount == model.values.map(\.count).reduce(0, +))
      for source in 1...9 as ClosedRange<UInt64> {
        #expect(graph.isStructural(id(source)) == structural.contains(source), "\(source)")
        graph.markDirty(id(source))
        let expected: Set<UInt64>?
        if !structural.contains(source) {
          expected = []
        } else if let sourceOwners = model[source], !sourceOwners.isEmpty {
          expected = sourceOwners
        } else {
          expected = nil
        }
        #expect(graph.dirtyOwners(of: id(source)) == expected)
        graph.clearDirty()
      }
    }
  }
}
