import SwiftUIWeb

/// Fixtures for the opt-in render-commit benchmark
/// (`Tools/test-performance-browser.mjs --render-commit`, `make render-commit-benchmark`).
///
/// Both routes are hidden from the sidebar and reached by path only:
/// `/renderBenchSmall` holds frequent small updates (counter, slider, text field) and
/// `/renderBenchList` holds a deterministic keyed list of 1000 rows with structural
/// operations in the style of js-framework-benchmark. Every control has a `data-testid`
/// (`accessibilityIdentifier`) so the benchmark drives it without depending on layout.
struct RenderCommitSmallUpdatesFixture: View {
  @State private var count = 0
  @State private var level = 0.0
  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Render-commit benchmark: small updates").font(.headline)
      HStack(spacing: 8) {
        Button("Increment") { count += 1 }
          .accessibilityIdentifier("bench-counter-increment")
        Text("Count: \(count)").accessibilityIdentifier("bench-counter-value")
      }
      Slider(value: $level, in: 0...100, step: 1)
        .accessibilityIdentifier("bench-slider")
      Text("Level: \(Int(level))").accessibilityIdentifier("bench-slider-value")
      TextField("Type here", text: $text)
        .accessibilityIdentifier("bench-text-field")
      Text("Echo: \(text)").accessibilityIdentifier("bench-text-echo")
      Text("Length: \(text.count)").accessibilityIdentifier("bench-text-length")
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct RenderCommitBenchmarkRow: Hashable {
  let id: Int
  var value: Int
}

struct RenderCommitListFixture: View {
  static let initialCount = 1000

  @State private var rows: [RenderCommitBenchmarkRow] = RenderCommitListFixture.makeRows(from: 0, count: RenderCommitListFixture.initialCount)
  @State private var nextID = RenderCommitListFixture.initialCount
  @State private var seed: UInt32 = 0x2545_F491
  @State private var operations = 0

  static func makeRows(from start: Int, count: Int) -> [RenderCommitBenchmarkRow] {
    var result: [RenderCommitBenchmarkRow] = []
    result.reserveCapacity(count)
    var id = start
    while id < start + count {
      result.append(RenderCommitBenchmarkRow(id: id, value: 0))
      id += 1
    }
    return result
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Render-commit benchmark: keyed list").font(.headline)
      HStack(spacing: 6) {
        Button("Insert head") { insert(at: 0) }.accessibilityIdentifier("bench-list-insert-head")
        Button("Insert middle") { insert(at: rows.count / 2) }.accessibilityIdentifier("bench-list-insert-middle")
        Button("Insert tail") { insert(at: rows.count) }.accessibilityIdentifier("bench-list-insert-tail")
        Button("Remove head") { remove(at: 0) }.accessibilityIdentifier("bench-list-remove-head")
        Button("Remove middle") { remove(at: rows.count / 2) }.accessibilityIdentifier("bench-list-remove-middle")
        Button("Remove tail") { remove(at: rows.count - 1) }.accessibilityIdentifier("bench-list-remove-tail")
      }
      HStack(spacing: 6) {
        Button("Swap") { swapRows() }.accessibilityIdentifier("bench-list-swap")
        Button("Reverse") { rows.reverse(); operations += 1 }.accessibilityIdentifier("bench-list-reverse")
        Button("Shuffle") { shuffle() }.accessibilityIdentifier("bench-list-shuffle")
        Button("Update every 10th") { update(stride: 10) }.accessibilityIdentifier("bench-list-update-partial")
        Button("Update all") { update(stride: 1) }.accessibilityIdentifier("bench-list-update-all")
        Button("Replace all") { replaceAll() }.accessibilityIdentifier("bench-list-replace-all")
        Button("Clear") { rows.removeAll(); operations += 1 }.accessibilityIdentifier("bench-list-clear")
        Button("Mount 1000") { replaceAll() }.accessibilityIdentifier("bench-list-mount")
      }
      Text("Rows: \(rows.count) · operations: \(operations)").accessibilityIdentifier("bench-list-state")
      VStack(alignment: .leading, spacing: 0) {
        ForEach(rows, id: \.id) { row in
          RenderCommitBenchmarkRowView(row: row)
        }
      }
      .accessibilityIdentifier("bench-list-rows")
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func insert(at index: Int) {
    rows.insert(RenderCommitBenchmarkRow(id: nextID, value: 0), at: min(max(index, 0), rows.count))
    nextID += 1
    operations += 1
  }

  private func remove(at index: Int) {
    guard !rows.isEmpty else { return }
    rows.remove(at: min(max(index, 0), rows.count - 1))
    operations += 1
  }

  private func swapRows() {
    // js-framework-benchmark "swap rows": the second and the second-to-last row.
    if rows.count > 3 { rows.swapAt(1, rows.count - 2) }
    operations += 1
  }

  private func shuffle() {
    // Deterministic Fisher-Yates driven by a xorshift32 sequence kept in state.
    var state = seed
    var index = rows.count - 1
    while index > 0 {
      state ^= state << 13
      state ^= state >> 17
      state ^= state << 5
      let other = Int(state % UInt32(index + 1))
      rows.swapAt(index, other)
      index -= 1
    }
    seed = state
    operations += 1
  }

  private func update(stride step: Int) {
    var index = 0
    while index < rows.count {
      rows[index].value += 1
      index += step
    }
    operations += 1
  }

  private func replaceAll() {
    rows = RenderCommitListFixture.makeRows(from: nextID, count: RenderCommitListFixture.initialCount)
    nextID += RenderCommitListFixture.initialCount
    operations += 1
  }
}

private struct RenderCommitBenchmarkRowView: View {
  let row: RenderCommitBenchmarkRow

  var body: some View {
    HStack(spacing: 8) {
      Text("Row \(row.id)")
      Spacer()
      Text("value \(row.value)")
    }
    .padding(.vertical, 2)
  }
}
