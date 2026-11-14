import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// Staged rendering (`_RenderStaging`) defers the children of a container once the render is deep and renders them
/// from the loop that drives the pass. It must change nothing but the call stack: the tree, identity, `@State`,
/// `onAppear`, preferences and the environment come out exactly as with plain recursion.
@Suite(.serialized)
@MainActor
struct RenderStagingTests {
  private final class Log {
    var appears: [String] = []
    var preferences: [[Int]] = []
  }

  private struct OrderKey: PreferenceKey {
    static let defaultValue: [Int] = []
    static func reduce(value: inout [Int], nextValue: () -> [Int]) { value.append(contentsOf: nextValue()) }
  }

  private struct Tint: ViewModifier {
    let value: String
    func body(content: Content) -> some View { content.environment(\.tint, value) }
  }

  /// One level: a staged container with a counter, a button, a preference write and the next level.
  private struct Level: View {
    let depth: Int
    let log: Log
    @State private var taps = 0
    @Environment(\.tint) private var tint

    var body: some View {
      if depth == 0 {
        Text("leaf \(tint)")
          .onAppear { log.appears.append("leaf") }
          .preference(key: OrderKey.self, value: [0])
      } else {
        _StagedContainer(
          Group {
            Text("L\(depth) taps \(taps) tint \(tint)")
              .preference(key: OrderKey.self, value: [depth * 10])
            Button("tap\(depth)") { taps += 1 }
            AnyView(Level(depth: depth - 1, log: log))
              .modifier(depth == 7 ? Tint(value: "seven") : Tint(value: tint))
            Text("after\(depth)")
              .preference(key: OrderKey.self, value: [depth * 10 + 1])
          }
        )
        .padding(1)
        .onAppear { log.appears.append("L\(depth)") }
      }
    }
  }

  private struct Root: View {
    let depth: Int
    let log: Log
    var body: some View {
      VStack {
        Level(depth: depth, log: log)
      }
      .onPreferenceChange(OrderKey.self) { log.preferences.append($0) }
    }
  }

  private func describe(_ node: _RenderNode, into out: inout [String], indent: Int = 0) {
    let pad = String(repeating: " ", count: indent)
    out.append("\(pad)\(node.kind.displayName)|\(node.text ?? "")|\(node.attributes.sorted { $0.key < $1.key })|\(node.styles.sorted { $0.key < $1.key })|\(node.classes)|\(node.key.map { "\($0)" } ?? "")|\(node.events.keys.sorted())")
    for child in node.children { describe(child, into: &out, indent: indent + 1) }
  }

  private func dump(_ tree: FiberTree) -> [String] {
    var lines: [String] = []
    describe(tree.renderNode, into: &lines)
    return lines
  }

  private func withBudget<T>(_ budget: Int, _ body: () -> T) -> T {
    let saved = _RenderStaging.budget
    _RenderStaging.budget = budget
    defer { _RenderStaging.budget = saved }
    return body()
  }

  private func clickAll(_ tree: FiberTree, _ labels: [String]) {
    for label in labels {
      guard let fiber = find(tree.root, label) else { Issue.record("missing \(label)"); continue }
      tree.dispatch(event: "click", at: fiber.identity)
      _ = tree.renderNode
    }
  }

  private func find(_ fiber: Fiber, _ label: String) -> Fiber? {
    if fiber.renderNode.attributes["data-control-kind"] == "button", texts(fiber.renderNode) == [label] { return fiber }
    for child in fiber.children { if let found = find(child, label) { return found } }
    return nil
  }

  private func texts(_ node: _RenderNode) -> [String] {
    if node.kind == .text, let text = node.text { return [text] }
    return node.children.flatMap(texts)
  }

  private func run(budget: Int, depth: Int = 40) -> (tree: [String], afterClicks: [String], log: Log, jobs: Int) {
    withBudget(budget) {
      let log = Log()
      let before = _RenderStaging.jobsCreated
      let tree = FiberTree(Root(depth: depth, log: log), deferLazyCollections: false)
      defer { tree._dispose() }
      let first = dump(tree)
      clickAll(tree, ["tap40", "tap39", "tap39", "tap7", "tap1", "tap7"])
      return (first, dump(tree), log, _RenderStaging.jobsCreated - before)
    }
  }

  @Test
  func stagedRenderProducesThePlainTree() {
    let plain = run(budget: 0)
    #expect(plain.jobs == 0)
    for budget in [1, 2, 5, 12] {
      let staged = run(budget: budget)
      #expect(staged.jobs > 0, "budget \(budget) should have deferred something")
      #expect(staged.tree == plain.tree, "budget \(budget): first render differs")
      #expect(staged.afterClicks == plain.afterClicks, "budget \(budget): render after clicks differs")
    }
  }

  @Test
  func stateKeepsItsIdentityAcrossDeferredBoundaries() {
    let staged = run(budget: 2)
    // Three taps landed in different levels, one of them twice; the counters live in the deferred levels.
    #expect(staged.afterClicks.contains { $0.contains("L40 taps 1") })
    #expect(staged.afterClicks.contains { $0.contains("L39 taps 2") })
    #expect(staged.afterClicks.contains { $0.contains("L7 taps 2") })
    #expect(staged.afterClicks.contains { $0.contains("L1 taps 1") })
  }

  @Test
  func lifecycleCallbacksRunOncePerViewAsWithPlainRecursion() {
    let plain = run(budget: 0)
    let staged = run(budget: 2)
    #expect(staged.log.appears.sorted() == plain.log.appears.sorted())
    #expect(Set(staged.log.appears).count == staged.log.appears.count)
    #expect(staged.log.appears.contains("leaf") && staged.log.appears.contains("L40"))
  }

  private struct SumKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
  }

  /// `content` under `depth` stacks: deep enough for the staged render to defer it.
  private struct Deep<Content: View>: View {
    let depth: Int
    let content: Content
    var body: some View {
      if depth == 0 { content } else { VStack { Deep(depth: depth - 1, content: content) } }
    }
  }

  // A subtree that transforms a preference reads only its own writes, though an earlier sibling's staged job writes late.
  @Test
  func aSubtreeBoundaryTakesIntoAccountWhatAnEarlierSiblingHasYetToWrite() {
    func total(budget: Int, depth: Int) -> Int {
      withBudget(budget) {
        var seen: [Int] = []
        let view = VStack {
          Deep(depth: depth, content: Text("a").preference(key: SumKey.self, value: 1))
          Deep(depth: depth, content: Text("b").preference(key: SumKey.self, value: 2)).transformPreference(SumKey.self) { $0 *= 10 }
        }
        .onPreferenceChange(SumKey.self) { seen.append($0) }
        let tree = FiberTree(view)
        defer { tree._dispose() }
        _ = tree.renderNode
        return seen.last ?? -1
      }
    }
    // Plain recursion: the sibling's 1, and the subtree's 2 made 20.
    #expect(total(budget: 0, depth: 8) == 21)
    for budget in [1, 2, 3, 4, 6] {
      for depth in [3, 6, 8] { #expect(total(budget: budget, depth: depth) == 21, "budget \(budget), depth \(depth)") }
    }
  }

  @Test
  func preferencesReduceInTheOrderOfPlainRecursion() {
    let plain = run(budget: 0)
    #expect(!plain.log.preferences.isEmpty)
    for budget in [1, 2, 3, 7] {
      let staged = run(budget: budget)
      #expect(staged.log.preferences == plain.log.preferences, "budget \(budget): preference order differs")
    }
  }

  @Test
  func environmentModifiersReachDeferredSubtrees() {
    let staged = run(budget: 2)
    // Level 7 sets the tint for everything below it; the levels above keep the default.
    #expect(staged.tree.contains { $0.contains("L8 taps 0 tint none") })
    #expect(staged.tree.contains { $0.contains("L6 taps 0 tint seven") })
    #expect(staged.tree.contains { $0.contains("leaf seven") })
  }

  private struct ToolbarLevel: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        Text("bottom").toolbar { Text("deep toolbar") }
      } else {
        _StagedContainer(Group {
          Text("level \(depth)")
          AnyView(ToolbarLevel(depth: depth - 1))
        })
      }
    }
  }

  /// A navigation stack collects the toolbars its content declares while it renders, and only while it does; the
  /// ones declared in deferred parts must be collected too, and land exactly where they do without staging.
  @Test
  func aNavigationStackCollectsToolbarsDeclaredInDeferredContent() {
    func render(budget: Int) -> (lines: [String], jobs: Int) {
      withBudget(budget) {
        let before = _RenderStaging.jobsCreated
        let tree = FiberTree(NavigationStack { ToolbarLevel(depth: 12) }, deferLazyCollections: false)
        defer { tree._dispose() }
        return (dump(tree), _RenderStaging.jobsCreated - before)
      }
    }
    let plain = render(budget: 0)
    #expect(plain.lines.contains { $0.contains("deep toolbar") })
    for budget in [1, 2, 4] {
      let staged = render(budget: budget)
      #expect(staged.jobs > 0, "budget \(budget) should have deferred something")
      #expect(staged.lines == plain.lines, "budget \(budget): the navigation stack differs")
    }
  }

  private struct Counter: View {
    @State private var local = 0
    var body: some View {
      Group {
        Text("local \(local)")
        Button("inc") { local += 1 }
      }
    }
  }

  /// Always equal to itself, so `EquatableView` would reuse its result forever if it did not see the state that
  /// `Counter`'s body reads, which happens in the deferred part.
  private struct ReadsStateInDeferredContent: Equatable, View {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
    var body: some View { _StagedContainer(Counter()) }
  }

  /// `EquatableView` reuses a result only if its content read no state; a deferred part of the content is part of it.
  @Test
  func equatableViewSeesWhatDeferredContentReads() {
    // Reuse is off in native builds (Observation reads are invisible to the store); this content reads only state.
    let savedReuse = _EquatableViewReuse.enabled
    _EquatableViewReuse.enabled = true
    defer { _EquatableViewReuse.enabled = savedReuse }
    func run(budget: Int) -> [String] {
      withBudget(budget) {
        let tree = FiberTree(ReadsStateInDeferredContent().equatable(), deferLazyCollections: false)
        defer { tree._dispose() }
        clickAll(tree, ["inc", "inc"])
        return dump(tree)
      }
    }
    let plain = run(budget: 0)
    #expect(plain.contains { $0.contains("local 2") })
    #expect(run(budget: 1) == plain)
  }

  @Test
  func readingChildrenRendersADeferredContainerOnTheSpot() {
    withBudget(1) {
      let log = Log()
      let tree = FiberTree(Root(depth: 6, log: log), deferLazyCollections: false, startLifecycle: false)
      defer { tree._dispose() }
      #expect(texts(tree.renderNode).contains("leaf none"))
    }
  }

  @Test
  func aDeepTreeNeedsOnlyAShallowRecursion() {
    withBudget(4) {
      let log = Log()
      let tree = FiberTree(Root(depth: 200, log: log), deferLazyCollections: false, startLifecycle: false)
      defer { tree._dispose() }
      #expect(texts(tree.renderNode).contains("leaf seven"))
      #expect(_RenderStaging.jobsCreated > 50)
      #expect(_RenderStaging.jobsRunFromLoop > 0, "the loop that drives the pass, not a reader, ran the jobs")
    }
  }
}

extension EnvironmentValues {
  fileprivate var tint: String {
    get { self[RenderStagingTintKey.self] }
    set { self[RenderStagingTintKey.self] = newValue }
  }
}

private struct RenderStagingTintKey: EnvironmentKey { static let defaultValue = "none" }

@MainActor
@Suite
struct RenderNodeReleaseTests {
  /// Freeing a deep tree must not recurse once per level: a view hierarchy hundreds of levels deep builds a tree
  /// that would otherwise need more stack to free than a WebKit Worker has.
  @Test
  func aVeryDeepNodeTreeFreesWithoutRecursingPerLevel() {
    var root: _RenderNode? = _RenderNode.element("div")
    var tip = root!
    for _ in 0..<200_000 {
      let child = _RenderNode.element("div")
      tip.children = [child]
      tip = child
    }
    tip = _RenderNode.empty()
    root = nil
    #expect(root == nil)
  }
}
