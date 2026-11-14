# Observation contract

SwiftUIWeb treats Observation as a renderer dependency transaction. A model
value never enters the dependency graph; only a stable numeric
`source` and the current erased-view `owner` are recorded.

## Terms

- **Source**: a stable numeric id for a piece of observed state (a `StateStore` slot or an Observation property) that a
  render reads. The model value itself never enters the dependency graph.
- **Owner**: the erased view whose body read a source during its render pass. A source read by an owner gives one
  `source → owner` edge.
- **Leaf binding**: a read the pass can prove is a direct leaf (one text or attribute value on one element). A change to it
  updates that value through the leaf queue, without re-evaluating a view body.
- **Root fallback**: a reconciliation from the root of the tree. It is used when a dirty source has no owner, or several,
  that can be narrowed to a retained subtree. It is a semantic result, not an error.

## Semantics

1. A source read inside an owner creates one `source → owner` edge for the
   current render pass. Repeated reads are set-like and do not duplicate the
   edge.
2. A source is structural when the pass cannot prove that the read is a
   direct leaf binding. Structural sources participate in subtree selection;
   proven leaf sources use the leaf queue and do not reevaluate a view body.
3. A dirty structural source with exactly one owner selects that owner. When
   several unique sources are dirty, their owner set is unioned and ancestor
   targets subsume descendants. This is the minimum safe retained subtree.
4. A source with no owner or more than one owner is shared/ambiguous and
   requires one root reconciliation. The root fallback is a semantic result,
   not an error.
5. Multiple writes during one renderer event are coalesced. The host receives
   one invalidation notification and drains one root/subtree/leaf commit after
   the final value is visible.
6. Replaced owners retire their edges at the end of the subtree pass. A
   disposed `StateStore` atomically resets its dependency graph,
   removes its source-index entries, detaches callbacks, cancels tasks and
   rejects later reads/writes. `FiberTree._dispose()` is idempotent and is the
   browser-session teardown boundary.

## Boundary invariants

- `_DependencyGraph` (`Sources/SwiftUIWebCore/DependencyGraph.swift`) owns the
  pending and committed dependency graph, indexed both by source and by owner,
  so retiring a replaced owner's edges costs that owner's edges rather than a
  scan of every source.
- `StateStore` owns typed model values, callbacks and orchestration; the graph
  holds source and owner integers only.
- The root fallback (`nil` from the owner queries) is a normal classification
  outcome. Beginning a pass while another is pending is a programmer error and
  traps.

## Executable coverage

- `Tests/SwiftUIWebTests/DependencyGraphTests.swift` tests unique owners,
  shared sources, unowned reads, subtree replacement, kept owners, coalescing
  and deterministic property-style fuzz cases.
- `Tests/SwiftUIWebTests/IncrementalDOMTests.swift` and
  `Tests/SwiftUIWebTests/PartialBehaviorTests.swift` assert minimum subtree,
  shared-source root fallback, coalescing and stale-owner behavior.
- `Tests/SwiftUIWebTests/MemoryBenchmarks.swift` and the runtime Swift Testing target
  assert teardown reaches zero live renderer objects.
- `make lowering-test` exercises the lowered `@Observable` path in a real
  Embedded Swift + BrowserIO bundle.
