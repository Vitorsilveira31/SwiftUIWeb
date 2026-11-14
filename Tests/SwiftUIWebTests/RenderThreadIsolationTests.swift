import Testing
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// Independent view graphs may be evaluated concurrently by native hosts
/// (parallel tests, tooling). The implicit render-pass state — installed
/// environment, state scope and memory counters — must never leak between
/// them.
@Suite
@MainActor
struct RenderThreadIsolationTests {
  fileprivate enum GraphLabelKey: EnvironmentKey { static let defaultValue = "none" }

  private struct Leaf: View {
    @Environment(\.graphLabel) private var label
    @State private var count = 0
    var body: some View { Text("\(label):\(count)") }
  }

  private struct Graph: View {
    let label: String
    @MainActor var body: some View {
      VStack { ForEach(0..<12, id: \.self) { _ in Leaf() } }
        .environment(\.graphLabel, label)
    }
  }

  /// Rendering is main-actor isolated, so independent graphs interleave on one
  /// executor instead of running on several threads. Each must still keep its own
  /// environment and state scope, and nothing may leak out of a render pass.
  @Test
  func graphsKeepTheirOwnEnvironmentAndState() {
    let labels = (0..<8).map { "graph-\($0)" }
    var mismatches = 0
    for _ in 0..<40 {
      for label in labels {
        let tree = FiberTree(Graph(label: label), deferLazyCollections: false, startLifecycle: false)
        let texts = Self.texts(in: tree.renderNode)
        mismatches += texts.filter { $0 != "\(label):0" }.count
        if texts.count != 12 { mismatches += 1 }
        tree._dispose()
      }
    }
    #expect(mismatches == 0)
    #expect(EnvironmentRuntime.installed == nil)
    #expect(StateRuntime.scope == nil)
  }

  @Test
  func memoryCountersBelongToTheRenderingThread() {
    _RuntimeMemoryMetrics.start()
    defer { _RuntimeMemoryMetrics.stop() }
    let tree = FiberTree(Graph(label: "measured"), deferLazyCollections: false, startLifecycle: false)
    _ = tree.renderNode
    let snapshot = _RuntimeMemoryMetrics.snapshot()
    #expect(snapshot.enabled)
    #expect(snapshot.renderNodeAllocations > 0)
    tree._dispose()
  }

  private static func texts(in node: _RenderNode) -> [String] {
    if node.kind == .text, let text = node.text { return [text] }
    return node.children.flatMap(texts)
  }
}

private extension EnvironmentValues {
  var graphLabel: String {
    get { self[RenderThreadIsolationTests.GraphLabelKey.self] }
    set { self[RenderThreadIsolationTests.GraphLabelKey.self] = newValue }
  }
}
