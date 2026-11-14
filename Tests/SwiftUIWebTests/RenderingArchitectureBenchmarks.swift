import Foundation
import Dispatch
import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// These are deliberately test-only models.  They make the cost difference
/// between whole-tree Fiber invalidation and leaf subscriptions measurable
/// without adding a second production renderer before the architecture is
/// decided.
private final class BenchmarkCounters {
  var rootBodies = 0
  var rowBodies = 0
}

private struct BenchmarkRow: Hashable {
  let id: Int
  let value: Int
}

private struct CounterView: View {
  let value: Int
  let counters: BenchmarkCounters
  var body: some View {
    counters.rootBodies += 1
    return Text("Count: \(value)")
  }
}

private struct RowsView: View {
  let rows: [BenchmarkRow]
  let counters: BenchmarkCounters
  var body: some View {
    counters.rootBodies += 1
    return ForEach(rows, id: \.id) { row in
      RowView(row: row, counters: counters)
    }
  }
}

private struct RowView: View {
  let row: BenchmarkRow
  let counters: BenchmarkCounters
  var body: some View {
    counters.rowBodies += 1
    return Text("Row \(row.id): \(row.value)")
  }
}

private struct FormView: View {
  let values: [BenchmarkRow]
  let counters: BenchmarkCounters
  var body: some View {
    counters.rootBodies += 1
    return ForEach(values, id: \.id) { value in Text("Field \(value.value)") }
  }
}

private struct DeepView: View {
  let depth: Int
  let value: Int
  let counters: BenchmarkCounters
  var body: some View {
    counters.rootBodies += 1
    if depth == 0 { return AnyView(Text("Leaf \(value)")) }
    return AnyView(DeepView(depth: depth - 1, value: value, counters: counters))
  }
}

private final class GranularCounters {
  var rootBodies = 0
  var rowBodies = 0
}

private struct GranularRow: View {
  let id: Int
  let counters: GranularCounters
  @State var value = 0
  var body: some View {
    counters.rowBodies += 1
    return Text("Granular \(id):\(value)")
  }
}

private struct GranularList: View {
  let rows: [GranularRow]
  let counters: GranularCounters
  var body: some View {
    counters.rootBodies += 1
    return ForEach(rows, id: \.id) { $0 }
  }
}

private struct StaticTemplateRows: View {
  let count: Int
  let counters: BenchmarkCounters
  var body: some View {
    counters.rootBodies += 1
    return ForEach(Array(0..<count), id: \.self) { _ in
      Text("Repeated static row")
    }
  }
}

private struct NonHoistableTemplateRows: View {
  let count: Int
  let counters: BenchmarkCounters
  var body: some View {
    counters.rootBodies += 1
    return ForEach(Array(0..<count), id: \.self) { _ in
      // The event-bearing control is an intentional baseline: lifecycle/event
      // metadata makes the subtree ineligible for static representation reuse.
      Button("Repeated static row") {}
    }
  }
}

private final class BenchmarkSignal<Value: Equatable> {
  private(set) var value: Value
  private var observers: [() -> Void] = []

  init(_ value: Value) { self.value = value }

  func set(_ newValue: Value) {
    guard value != newValue else { return }
    value = newValue
    observers.forEach { $0() }
  }

  func observe(_ effect: @escaping () -> Void) {
    observers.append(effect)
    effect()
  }
}

private final class MutationProbe {
  var textMutations = 0
  var currentText = ""

  func setText(_ text: String) {
    currentText = text
    textMutations += 1
  }
}

@Observable private final class ObservationBenchmarkItem {
  let id: Int
  var value: Int

  init(id: Int, value: Int) {
    self.id = id
    self.value = value
  }
}

@Observable private final class ObservationBenchmarkModel {
  var items: [ObservationBenchmarkItem]

  init(items: [ObservationBenchmarkItem]) {
    self.items = items
  }
}

private final class ObservationBenchmarkCounters {
  var listBodies = 0
  var rowBodies = 0
}

private struct ObservationBenchmarkRow: View {
  let item: ObservationBenchmarkItem
  let counters: ObservationBenchmarkCounters

  var body: some View {
    counters.rowBodies += 1
    return Text("Item \(item.id):\(item.value)")
  }
}

private struct ObservationBenchmarkList: View {
  let model: ObservationBenchmarkModel
  let counters: ObservationBenchmarkCounters

  var body: some View {
    counters.listBodies += 1
    return ForEach(model.items, id: \.id) { item in
      ObservationBenchmarkRow(item: item, counters: counters)
    }
  }
}

private struct BenchmarkResult {
  let workload: String
  let architecture: String
  let iterations: Int
  let nanoseconds: UInt64
  let bodyEvaluations: Int
  let renderNodesVisited: Int
  let reconciliationOperations: Int
  let domMutations: Int
  let signalEffects: Int

  var csv: String {
    [workload, architecture, String(iterations), String(nanoseconds),
     String(bodyEvaluations), String(renderNodesVisited),
     String(reconciliationOperations), String(domMutations),
     String(signalEffects)].joined(separator: ",")
  }
}

private func countNodes(_ node: _RenderNode) -> Int {
  1 + node.children.reduce(0) { $0 + countNodes($1) }
}

private func recordBenchmark(
  workload: String,
  architecture: String,
  iterations: Int,
  bodyEvaluations: Int,
  renderNodesVisited: Int,
  reconciliationOperations: Int,
  domMutations: Int,
  signalEffects: Int,
  _ operation: () -> Void
) -> BenchmarkResult {
  let start = DispatchTime.now().uptimeNanoseconds
  operation()
  let elapsed = DispatchTime.now().uptimeNanoseconds - start
  return BenchmarkResult(
    workload: workload,
    architecture: architecture,
    iterations: iterations,
    nanoseconds: elapsed,
    bodyEvaluations: bodyEvaluations,
    renderNodesVisited: renderNodesVisited,
    reconciliationOperations: reconciliationOperations,
    domMutations: domMutations,
    signalEffects: signalEffects
  )
}

@Suite
@MainActor
final class RenderingArchitectureBenchmarks {
  /// Run with `swift test -c release --filter RenderingArchitectureBenchmarks`
  /// to produce a compact CSV suitable for comparing toolchains.  The signal
  /// rows are an idealized leaf-binding prototype, not a claim that the
  /// production SwiftUI API already creates these subscriptions.
  @Test
  func testBenchmarkMatrix() {
    let iterations = 100
    let listSize = 500
    var results: [BenchmarkResult] = []

    do {
      let counters = BenchmarkCounters()
      let tree = FiberTree(CounterView(value: 0, counters: counters))
      var mutations = 0
      var visited = countNodes(tree.root.renderNode)
      let result = recordBenchmark(workload: "counter", architecture: "fiber", iterations: iterations,
                           bodyEvaluations: 0, renderNodesVisited: 0,
                           reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations {
          let batch = tree.update(CounterView(value: value, counters: counters))
          mutations += batch.count
          visited += countNodes(tree.root.renderNode)
        }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: counters.rootBodies,
                                     renderNodesVisited: visited,
                                     reconciliationOperations: mutations,
                                     domMutations: mutations, signalEffects: 0))
    }

    do {
      let signal = BenchmarkSignal(0)
      let probe = MutationProbe()
      var effects = 0
      signal.observe { effects += 1; probe.setText("Count: \(signal.value)") }
      let result = recordBenchmark(workload: "counter", architecture: "fine-grained", iterations: iterations,
                           bodyEvaluations: 0, renderNodesVisited: 0,
                           reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations { signal.set(value) }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: 0, renderNodesVisited: 0,
                                     reconciliationOperations: 0, domMutations: probe.textMutations - 1,
                                     signalEffects: effects - 1))
    }

    do {
      // Compile-time systems such as Svelte can lower this expression to a
      // direct assignment. This is the lower bound for a generated update;
      // there is intentionally no dependency graph or view evaluation here.
      let probe = MutationProbe()
      let result = recordBenchmark(workload: "counter", architecture: "svelte-generated", iterations: iterations,
                                   bodyEvaluations: 0, renderNodesVisited: 0,
                                   reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations { probe.setText("Count: \(value)") }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: 0, renderNodesVisited: 0,
                                     reconciliationOperations: 0, domMutations: probe.textMutations,
                                     signalEffects: 0))
    }

    do {
      // Qwik's resumable path still has a direct DOM write after a lazy event
      // handler is loaded. This models the post-resume event cost only; the
      // download/parse cost is measured separately in a browser harness.
      let probe = MutationProbe()
      let result = recordBenchmark(workload: "counter", architecture: "qwik-resumable", iterations: iterations,
                                   bodyEvaluations: 0, renderNodesVisited: 0,
                                   reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations { probe.setText("Count: \(value)") }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: 0, renderNodesVisited: 0,
                                     reconciliationOperations: 0, domMutations: probe.textMutations,
                                     signalEffects: 0))
    }

    do {
      let rows = (0..<listSize).map { BenchmarkRow(id: $0, value: 0) }
      let counters = BenchmarkCounters()
      let tree = FiberTree(RowsView(rows: rows, counters: counters))
      var mutationCount = 0
      var visited = countNodes(tree.root.renderNode)
      let result = recordBenchmark(workload: "large-list-one-row", architecture: "fiber", iterations: iterations,
                           bodyEvaluations: 0, renderNodesVisited: 0,
                           reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations {
          var next = rows
          next[rows.count / 2] = BenchmarkRow(id: rows.count / 2, value: value)
          let batch = tree.update(RowsView(rows: next, counters: counters))
          mutationCount += batch.count
          visited += countNodes(tree.root.renderNode)
        }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: counters.rootBodies + counters.rowBodies,
                                     renderNodesVisited: visited,
                                     reconciliationOperations: mutationCount,
                                     domMutations: mutationCount, signalEffects: 0))
    }

    do {
      let signals = (0..<listSize).map { _ in BenchmarkSignal(0) }
      let probe = MutationProbe()
      var effects = 0
      for (index, signal) in signals.enumerated() {
        signal.observe { effects += 1; probe.setText("Row \(index): \(signal.value)") }
      }
      let result = recordBenchmark(workload: "large-list-one-row", architecture: "fine-grained", iterations: iterations,
                           bodyEvaluations: 0, renderNodesVisited: 0,
                           reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations { signals[signals.count / 2].set(value) }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: 0, renderNodesVisited: 0,
                                     reconciliationOperations: 0, domMutations: probe.textMutations - listSize,
                                     signalEffects: effects - listSize))
    }

    do {
      let probe = MutationProbe()
      let result = recordBenchmark(workload: "large-list-one-row", architecture: "svelte-generated", iterations: iterations,
                                   bodyEvaluations: 0, renderNodesVisited: 0,
                                   reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations { probe.setText("Row \(listSize / 2): \(value)") }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: 0, renderNodesVisited: 0,
                                     reconciliationOperations: 0, domMutations: probe.textMutations,
                                     signalEffects: 0))
    }

    do {
      // Vue-style component effects retain a structural table but use a
      // reactive ref for a stable leaf. This is intentionally the same
      // operation as the custom hybrid, named separately for comparison.
      let signals = (0..<listSize).map { _ in BenchmarkSignal(0) }
      let probe = MutationProbe()
      var effects = 0
      for (index, signal) in signals.enumerated() {
        signal.observe { effects += 1; probe.setText("Row \(index): \(signal.value)") }
      }
      let result = recordBenchmark(workload: "large-list-one-row", architecture: "vue-hybrid", iterations: iterations,
                                   bodyEvaluations: 0, renderNodesVisited: 0,
                                   reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations { signals[signals.count / 2].set(value) }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: 0, renderNodesVisited: 0,
                                     reconciliationOperations: 0,
                                     domMutations: probe.textMutations - listSize,
                                     signalEffects: effects - listSize))
    }

    do {
      let counters = BenchmarkCounters()
      let first = Array(0..<listSize)
      let tree = FiberTree(ForEach(first, id: \.self) { value in Text("\(value)") })
      var mutationCount = 0
      let result = recordBenchmark(workload: "list-reorder", architecture: "fiber", iterations: 1,
                           bodyEvaluations: 0, renderNodesVisited: 0,
                           reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        let reordered = Array(first.reversed())
        mutationCount += tree.update(ForEach(reordered, id: \.self) { value in Text("\(value)") }).count
      }
      _ = counters
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: 0, renderNodesVisited: 0,
                                     reconciliationOperations: mutationCount,
                                     domMutations: mutationCount, signalEffects: 0))
    }

    do {
      // A hybrid keeps keyed structure in a Fiber-like table but gives each
      // stable row a direct value subscription.
      let keys = Array(0..<listSize)
      let signals = Dictionary(uniqueKeysWithValues: keys.map { ($0, BenchmarkSignal(0)) })
      let probe = MutationProbe()
      var effects = 0
      for key in keys {
        signals[key]?.observe { effects += 1; probe.setText("Row \(key): \(signals[key]!.value)") }
      }
      let result = recordBenchmark(workload: "large-list-one-row", architecture: "hybrid", iterations: iterations,
                           bodyEvaluations: 0, renderNodesVisited: 0,
                           reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations { signals[keys.count / 2]?.set(value) }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: 0, renderNodesVisited: 0,
                                     reconciliationOperations: 0,
                                     domMutations: probe.textMutations - listSize,
                                     signalEffects: effects - listSize))
    }

    do {
      let counters = BenchmarkCounters()
      let values = (0..<100).map { BenchmarkRow(id: $0, value: 0) }
      let tree = FiberTree(FormView(values: values, counters: counters))
      var mutationCount = 0
      let result = recordBenchmark(workload: "many-fields", architecture: "fiber", iterations: iterations,
                           bodyEvaluations: 0, renderNodesVisited: 0,
                           reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations {
          mutationCount += tree.update(FormView(values: values.map { $0.id == 50 ? BenchmarkRow(id: $0.id, value: value) : $0 }, counters: counters)).count
        }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: counters.rootBodies,
                                     renderNodesVisited: 0,
                                     reconciliationOperations: mutationCount,
                                     domMutations: mutationCount, signalEffects: 0))
    }

    do {
      let signals = (0..<100).map { _ in BenchmarkSignal(0) }
      let probe = MutationProbe()
      var effects = 0
      for (index, signal) in signals.enumerated() {
        signal.observe { effects += 1; probe.setText("Field \(index): \(signal.value)") }
      }
      let result = recordBenchmark(workload: "many-fields", architecture: "fine-grained", iterations: iterations,
                           bodyEvaluations: 0, renderNodesVisited: 0,
                           reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations { signals[50].set(value) }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: 0, renderNodesVisited: 0,
                                     reconciliationOperations: 0,
                                     domMutations: probe.textMutations - signals.count,
                                     signalEffects: effects - signals.count))
    }

    do {
      let counters = BenchmarkCounters()
      let tree = FiberTree(DeepView(depth: 40, value: 0, counters: counters))
      var mutationCount = 0
      let result = recordBenchmark(workload: "deep-tree", architecture: "fiber", iterations: iterations,
                           bodyEvaluations: 0, renderNodesVisited: 0,
                           reconciliationOperations: 0, domMutations: 0, signalEffects: 0) {
        for value in 1...iterations { mutationCount += tree.update(DeepView(depth: 40, value: value, counters: counters)).count }
      }
      results.append(BenchmarkResult(workload: result.workload, architecture: result.architecture,
                                     iterations: result.iterations, nanoseconds: result.nanoseconds,
                                     bodyEvaluations: counters.rootBodies,
                                     renderNodesVisited: 0,
                                     reconciliationOperations: mutationCount,
                                     domMutations: mutationCount, signalEffects: 0))
    }

    print("workload,architecture,iterations,nanoseconds,bodyEvaluations,renderNodesVisited,reconciliationOperations,domMutations,signalEffects")
    results.forEach { print($0.csv) }

    _expectEqual(results.count, 13)
    _expectEqual(results.first(where: { $0.workload == "counter" && $0.architecture == "fine-grained" })?.domMutations, iterations)
    _expectEqual(results.first(where: { $0.workload == "large-list-one-row" && $0.architecture == "fine-grained" })?.domMutations, iterations)
    _expectEqual(results.first(where: { $0.workload == "counter" && $0.architecture == "svelte-generated" })?.domMutations, iterations)
  }

  /// Compares the old root-refresh shape with owner-scoped structural
  /// invalidation for a deep list. This is a release benchmark: the printed
  /// deltas are intentionally simple enough to compare across toolchains.
  @Test
  func testHierarchicalInvalidationBenchmark() {
    let count = 500
    let iterations = 40
    let baselineCounters = BenchmarkCounters()
    var baselineRows = (0..<count).map { BenchmarkRow(id: $0, value: 0) }
    let baseline = FiberTree(RowsView(rows: baselineRows, counters: baselineCounters))
    let baselineBodies = baselineCounters.rowBodies
    let baselineStart = DispatchTime.now().uptimeNanoseconds
    for value in 1...iterations {
      baselineRows = baselineRows.map { $0.id == count / 2 ? BenchmarkRow(id: $0.id, value: value) : $0 }
      _ = baseline.update(RowsView(rows: baselineRows, counters: baselineCounters))
    }
    let baselineElapsed = DispatchTime.now().uptimeNanoseconds - baselineStart
    let baselineRowDelta = baselineCounters.rowBodies - baselineBodies

    let granularCounters = GranularCounters()
    let granularRows = (0..<count).map { GranularRow(id: $0, counters: granularCounters) }
    let granular = FiberTree(GranularList(rows: granularRows, counters: granularCounters))
    let granularBodies = granularCounters.rowBodies
    var hostInvalidations = 0
    granular.setExternalInvalidationHandler({ hostInvalidations += 1 }, deferUpdates: true)
    let granularStart = DispatchTime.now().uptimeNanoseconds
    for value in 1...iterations {
      granularRows[count / 2].value = value
      _ = granular._drainSubtreeUpdates()
    }
    let granularElapsed = DispatchTime.now().uptimeNanoseconds - granularStart
    let granularRowDelta = granularCounters.rowBodies - granularBodies

    print("hierarchical,rows=\(count),iterations=\(iterations),baselineNs=\(baselineElapsed),granularNs=\(granularElapsed),baselineRowBodies=\(baselineRowDelta),granularRowBodies=\(granularRowDelta),baselineBodyEvaluations=\(baseline.metrics.bodyEvaluations),granularBodyEvaluations=\(granular.metrics.bodyEvaluations),baselineNodesVisited=\(baseline.metrics.structuralNodeVisits),granularNodesVisited=\(granular.metrics.structuralNodeVisits),baselineInvalidatedNodes=\(baseline.metrics.invalidatedNodes),granularInvalidatedNodes=\(granular.metrics.invalidatedNodes),baselineReconciledNodes=\(baseline.metrics.reconciledNodes),granularReconciledNodes=\(granular.metrics.reconciledNodes),baselineRenderNodeAllocations=\(baseline.metrics.renderNodeAllocations),granularRenderNodeAllocations=\(granular.metrics.renderNodeAllocations),hostInvalidations=\(hostInvalidations),baselineReconcile=\(baseline.metrics.reconciliationOperations),granularReconcile=\(granular.metrics.reconciliationOperations)")
    _expectEqual(hostInvalidations, iterations)
    _expectEqual(granularRowDelta, iterations)
    _expectEqual(baselineRowDelta, count * iterations)
    _expectLessThan(granularRowDelta, baselineRowDelta)
    _expectLessThan(granular.metrics.structuralNodeVisits, baseline.metrics.structuralNodeVisits)
    _expectLessThan(granular.metrics.renderNodeAllocations, baseline.metrics.renderNodeAllocations)
    _expectEqual(granular.metrics.schedulerSubtreeFlushes, iterations)
  }

  /// Exercises semantic template hoisting with repeated, lifecycle-free rows.
  /// Swift still evaluates the source body (and therefore the candidate
  /// RenderNodes), but reconciliation retains the existing static graph and
  /// skips every unchanged descendant. This is the safe runtime limit until a
  /// compiler can prove view captures independently of evaluation.
  @Test
  func testStaticTemplateHoistingBenchmark() {
    let count = 500
    let iterations = 25
    let baselineCounters = BenchmarkCounters()
    let baseline = FiberTree(NonHoistableTemplateRows(count: count, counters: baselineCounters))
    let baselineStart = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
      _ = baseline.update(NonHoistableTemplateRows(count: count, counters: baselineCounters))
    }
    let baselineElapsed = DispatchTime.now().uptimeNanoseconds - baselineStart

    let counters = BenchmarkCounters()
    let tree = FiberTree(StaticTemplateRows(count: count, counters: counters))
    let initialBodies = counters.rootBodies
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
      _ = tree.update(StaticTemplateRows(count: count, counters: counters))
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start

    print("static-hoisting,rows=\(count),iterations=\(iterations),baselineNs=\(baselineElapsed),hoistedNs=\(elapsed),baselineBodyEvaluations=\(baseline.metrics.bodyEvaluations),hoistedBodyEvaluations=\(tree.metrics.bodyEvaluations),baselineRenderNodeAllocations=\(baseline.metrics.renderNodeAllocations),hoistedRenderNodeAllocations=\(tree.metrics.renderNodeAllocations),baselineStructuralVisits=\(baseline.metrics.structuralNodeVisits),hoistedStructuralVisits=\(tree.metrics.structuralNodeVisits),staticCandidates=\(tree.metrics.staticTemplateCandidates),staticHits=\(tree.metrics.staticTemplateHits),staticReuses=\(tree.metrics.staticTemplateReuses),domMutations=\(tree.metrics.domOperations)")
    _expectEqual(counters.rootBodies - initialBodies, iterations)
    _expectGreaterThan(tree.metrics.staticTemplateHits, 0)
    _expectGreaterThan(tree.metrics.staticTemplateReuses, 0)
    _expectLessThan(tree.metrics.structuralNodeVisits, baseline.metrics.structuralNodeVisits)
    _expectEqual(tree.lastMutations.count, 0)
  }

  /// Measures the dependency shape used by observation-heavy list screens.
  /// Each row owns a native Observation access list, so changing one item
  /// should reevaluate that row without reevaluating the list body or its
  /// siblings.
  @Test
  func testObservationHeavyListAvoidsUnnecessaryRerenders() {
    let iterations = 200
    let itemCount = 100
    let items = (0..<itemCount).map { ObservationBenchmarkItem(id: $0, value: 0) }
    let model = ObservationBenchmarkModel(items: items)
    let counters = ObservationBenchmarkCounters()
    let tree = FiberTree(ObservationBenchmarkList(model: model, counters: counters))
    let initialListBodies = counters.listBodies
    let initialRowBodies = counters.rowBodies
    let start = DispatchTime.now().uptimeNanoseconds

    for iteration in 0..<iterations {
      model.items[iteration % itemCount].value = iteration + 1
      _ = tree.renderNode
    }

    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    print("observation-list,iterations=\(iterations),items=\(itemCount),nanoseconds=\(elapsed),listBodies=\(counters.listBodies - initialListBodies),rowBodies=\(counters.rowBodies - initialRowBodies),invalidatedNodes=\(tree.metrics.invalidatedNodes),reconciledNodes=\(tree.metrics.reconciledNodes),subtreeFlushes=\(tree.metrics.schedulerSubtreeFlushes),rootFlushes=\(tree.metrics.schedulerStructuralFlushes)")
    _expectEqual(counters.listBodies, initialListBodies)
    _expectEqual(counters.rowBodies - initialRowBodies, iterations)
    _expectEqual(tree.metrics.schedulerStructuralFlushes, 0)
    _expectEqual(tree.metrics.schedulerSubtreeFlushes, iterations)
  }
}
