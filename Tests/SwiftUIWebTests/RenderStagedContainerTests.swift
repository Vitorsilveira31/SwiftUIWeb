import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@testable @_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// Identity paths, order tags and the containers that build in stages (navigation stacks, tab views, pickers,
/// `EquatableView`). The path and tag types are exercised on their own; the containers are rendered with staging off
/// (plain recursion) and with a small budget, which cuts the render everywhere, and must come out the same.
@Suite(.serialized)
@MainActor
struct RenderStagedContainerTests {
  // MARK: identity paths

  @Test
  func aPathEqualsAnotherBuiltFromTheSameKeys() {
    let keys = (0..<50).map { _FiberKey($0 % 7 == 0 ? "k\($0)" : String($0)) }
    let first = _FiberPath(keys)
    var second = _FiberPath()
    for key in keys { second.append(key) }
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
    #expect(Set([first, second]).count == 1)
    #expect(first.keys == keys)
    #expect(first.count == keys.count)
    #expect(first.last == keys.last)
    #expect(first != first.parent)
    #expect(first.parent.keys == Array(keys.dropLast()))
    // One key different anywhere makes a different path.
    var other = keys
    other[20] = _FiberKey("different")
    #expect(_FiberPath(other) != first)
    #expect(_FiberPath(Array(keys.dropFirst())) != first)
  }

  @Test
  func theTextOfAPathAskedForInnerFirstIsTheSameAsItsKeysJoined() {
    // Checkpoint links remember their text on the way up, so a path whose ancestors were never asked for builds from the
    // nearest one; the text must still be every key from the root.
    let keys = (0..<400).map { _FiberKey($0 % 5 == 0 ? "k\($0)" : String($0)) }
    var paths: [_FiberPath] = []
    var path = _FiberPath()
    for key in keys { path.append(key); paths.append(path) }
    for index in [399, 130, 64, 63, 65, 200, 0, 1, 128, 129, 300] {
      let expected = keys.prefix(index + 1).map(fiberKeyDescription).joined(separator: "/")
      #expect(paths[index].description == expected, "depth \(index + 1)")
    }
    // Asked again, and for a path that extends one that is now described.
    #expect(paths[399].description == keys.map(fiberKeyDescription).joined(separator: "/"))
    #expect(paths[399].appending(_FiberKey("tail")).description == keys.map(fiberKeyDescription).joined(separator: "/") + "/tail")
  }

  @Test
  func recordingStateScopePathsKeepsEachOnceInTheOrderRecorded() {
    // A chain of modifiers renders into one node that records the path of every level: past a handful it keeps a set
    // of them. The list must be what a linear search would have kept, also after the node is copied or replaced.
    let node = _RenderNode.element("div")
    var expected: [_FiberPath] = []
    var path = _FiberPath()
    for level in 0..<300 {
      path.append(_FiberKey(level))
      expected.append(path)
      _recordStateScopePath(node, path: path)
      _recordStateScopePath(node, path: _FiberPath(path.keys))   // an equal path built separately
      if level % 7 == 0 { _recordStateScopePath(node, path: expected[level / 2]) }
    }
    #expect(node._stateScopePaths == expected)
    let copy = node.cloneSharingChildren()
    let extra = path.appending(_FiberKey("more"))
    _recordStateScopePath(copy, path: extra)
    _recordStateScopePath(copy, path: expected[100])
    #expect(copy._stateScopePaths == expected + [extra])
    #expect(node._stateScopePaths == expected)
    // Replacing the list from outside drops what was known about the old one.
    node._stateScopePaths = [expected[0]]
    _recordStateScopePath(node, path: expected[0])
    _recordStateScopePath(node, path: expected[250])
    #expect(node._stateScopePaths == [expected[0], expected[250]])
  }

  @Test
  func aPathDescribesItselfAsItsKeysJoinedBySlashes() {
    let keys = [_FiberKey("root"), _FiberKey(3), _FiberKey(""), _FiberKey("x"), _FiberKey(true)]
    let path = _FiberPath(keys)
    #expect(path.description == keys.map(fiberKeyDescription).joined(separator: "/"))
    // The text of a path that extends a described one is built on the one that is known.
    let longer = path.appending(_FiberKey("tail"))
    #expect(longer.description == keys.map(fiberKeyDescription).joined(separator: "/") + "/tail")
    #expect(_FiberPath().description == "")
    #expect(_FiberPath([_FiberKey("only")]).description == "only")
  }

  @Test
  func aPathIsAPrefixOfThePathsBelowIt() {
    let keys = (0..<10).map { _FiberKey($0) }
    let full = _FiberPath(keys)
    for count in 0...10 {
      #expect(_FiberPath(Array(keys.prefix(count))).isPrefix(of: full), "prefix \(count)")
    }
    #expect(!full.isPrefix(of: _FiberPath(Array(keys.prefix(5)))))
    #expect(!_FiberPath([_FiberKey(99)]).isPrefix(of: full))
  }

  @Test
  func aVeryDeepPathIsFreedWithoutRecursingPerLevel() {
    var path = _FiberPath()
    for index in 0..<400_000 { path.append(_FiberKey(index)) }
    #expect(path.count == 400_000)
    path = _FiberPath()
    #expect(path.isEmpty)
  }

  @Test
  func appendingToAPathCostsTheSameAtAnyDepth() {
    // Paths that grow from a shared parent share it: the context a view renders in and its children do not copy keys.
    let base = _FiberPath((0..<1000).map { _FiberKey($0) })
    let a = base.appending(_FiberKey("a"))
    let b = base.appending(_FiberKey("b"))
    #expect(a.parent == base)
    #expect(b.parent == base)
    #expect(a != b)
    #expect(a.count == 1001)
  }

  // MARK: order tags

  private func lexicographic(_ lhs: [Int], _ rhs: [Int]) -> Int {
    var index = 0
    while index < lhs.count, index < rhs.count {
      if lhs[index] != rhs[index] { return lhs[index] < rhs[index] ? -1 : 1 }
      index += 1
    }
    return lhs.count == rhs.count ? 0 : (lhs.count < rhs.count ? -1 : 1)
  }

  private func tag(_ numbers: [Int], onto base: _OrderTag = _OrderTag()) -> _OrderTag {
    var result = base
    for number in numbers { result = result.appending(number) }
    return result
  }

  @Test
  func orderTagsCompareLikeArraysOfIntegers() {
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func next(_ bound: Int) -> Int {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return Int((seed >> 33) % UInt64(bound))
    }
    var lists: [[Int]] = [[]]
    for _ in 0..<150 { lists.append((0..<next(7)).map { _ in next(4) }) }
    // Many of them extend one prefix, so the tags share links as the real ones do.
    let prefix = [1, 2, 3]
    let shared = tag(prefix)
    for left in lists {
      for right in lists {
        let expected = lexicographic(left, right)
        let sign = tag(left).compare(to: tag(right))
        #expect((sign < 0) == (expected < 0) && (sign > 0) == (expected > 0), "\(left) vs \(right)")
        let sharedSign = tag(left, onto: shared).compare(to: tag(right, onto: shared))
        #expect((sharedSign < 0) == (expected < 0) && (sharedSign > 0) == (expected > 0), "shared \(left) vs \(right)")
        #expect((tag(left) == tag(right)) == (left == right))
      }
    }
  }

  @Test
  func theStableSortKeepsEqualElementsInTheirOrderAndIsLinearOnSortedInput() {
    struct Item { var key: Int; var order: Int }
    var items: [Item] = []
    var seed: UInt64 = 42
    for order in 0..<2000 {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      items.append(Item(key: Int((seed >> 40) % 20), order: order))
    }
    var sorted = items
    _stableSort(&sorted) { $0.key < $1.key }
    for (a, b) in zip(sorted, sorted.dropFirst()) {
      #expect(a.key < b.key || (a.key == b.key && a.order < b.order))
    }
    // Already sorted input is a single pass.
    var comparisons = 0
    var again = sorted
    _stableSort(&again) { comparisons += 1; return $0.key < $1.key }
    #expect(comparisons == sorted.count - 1)
    #expect(again.map(\.order) == sorted.map(\.order))
    // The reverse is the worst case for an insertion sort and still `n log n`.
    var reversed = Array(sorted.reversed())
    comparisons = 0
    _stableSort(&reversed) { comparisons += 1; return $0.key < $1.key }
    #expect(comparisons < 2000 * 16)
  }

  @Test
  func aVeryDeepOrderTagIsFreedWithoutRecursingPerLevel() {
    var deep = _OrderTag()
    for index in 0..<400_000 { deep = deep.appending(index) }
    #expect(deep.count == 400_000)
    deep = _OrderTag()
    #expect(deep.isEmpty)
  }

  // MARK: shared helpers

  private func describe(_ node: _RenderNode, into out: inout [String]) {
    var stack: [(node: _RenderNode, indent: Int)] = [(node, 0)]
    while let (node, indent) = stack.popLast() {
      let pad = String(repeating: " ", count: indent)
      out.append("\(pad)\(node.kind.displayName)|\(node.text ?? "")|\(node.attributes.sorted { $0.key < $1.key })|\(node.styles.sorted { $0.key < $1.key })|\(node.classes)|\(node.key.map { "\($0)" } ?? "")|\(node.events.keys.sorted())|\(node._stateScopePaths)|\(node._renderOwnerToken != nil)")
      for child in node.children.reversed() { stack.append((child, indent + 1)) }
    }
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

  private func find(_ fiber: Fiber, where matches: (_RenderNode) -> Bool) -> Fiber? {
    var stack = [fiber]
    while let current = stack.popLast() {
      if matches(current.renderNode) { return current }
      stack.append(contentsOf: current.children.reversed())
    }
    return nil
  }

  private let budgets = [1, 2, 3, 5, 12]

  private func texts(_ node: _RenderNode) -> [String] {
    var found: [String] = []
    var stack = [node]
    while let current = stack.popLast() {
      if current.kind == .text, let text = current.text { found.append(text) }
      stack.append(contentsOf: current.children.reversed())
    }
    return found
  }

  /// The first element that handles a click and whose text is `label`.
  private func clickable(_ tree: FiberTree, _ label: String) -> Fiber? {
    find(tree.root) { $0.events["click"] != nil && texts($0) == [label] }
  }

  // MARK: navigation stacks

  /// A stack inside a stack, each declaring a title and a toolbar; the title of the outer one is also set from outside
  /// the inner stack, which writes the same attribute on the inner stack's node after the inner stack did.
  private struct NestedStacks: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        Text("innermost").toolbar { Text("innermost bar") }
      } else {
        NavigationStack {
          AnyView(NestedStacks(depth: depth - 1))
            .navigationTitle("level \(depth)")
            .toolbar { Text("bar \(depth)") }
        }
        .navigationTitle("outside \(depth)")
      }
    }
  }

  @Test
  func nestedNavigationStacksKeepTheTitlesAndToolbarsTheyHadWithPlainRecursion() {
    func tree(budget: Int) -> [String] {
      withBudget(budget) {
        let tree = FiberTree(NestedStacks(depth: 6), deferLazyCollections: false)
        defer { tree._dispose() }
        return dump(tree)
      }
    }
    let plain = tree(budget: 0)
    #expect(plain.contains { $0.contains("data-navigation-title") && $0.contains("outside") })
    for budget in budgets { #expect(tree(budget: budget) == plain, "budget \(budget)") }
  }

  private struct PushedScreens: View {
    @State private var path = NavigationPath()
    var body: some View {
      NavigationStack(path: $path) {
        VStack {
          AnyView(Deep(depth: 14)).navigationTitle("root")
          NavigationLink("one", value: 1)
          NavigationLink("two", value: 2)
        }
      }
      .navigationDestination(for: Int.self) { value in
        AnyView(Deep(depth: 9)).navigationTitle("screen \(value)").toolbar { Text("bar \(value)") }
      }
    }
  }

  private struct Deep: View {
    let depth: Int
    var body: some View {
      if depth == 0 { Text("deep leaf") } else { AnyView(Deep(depth: depth - 1)).opacity(0.9).padding(1) }
    }
  }

  @Test
  func pushedDestinationsCollectTheirOwnToolbarsAsWithPlainRecursion() {
    func run(budget: Int) -> [[String]] {
      withBudget(budget) {
        let tree = FiberTree(PushedScreens(), deferLazyCollections: false)
        defer { tree._dispose() }
        var stages = [dump(tree)]
        for label in ["one", "two"] {
          guard let link = clickable(tree, label) else {
            Issue.record("missing link \(label)")
            continue
          }
          tree.dispatch(event: "click", at: link.identity)
          _ = tree.renderNode
          stages.append(dump(tree))
        }
        return stages
      }
    }
    let plain = run(budget: 0)
    #expect(plain.count == 3)
    #expect(plain.last?.contains { $0.contains("deep leaf") && true } == true)
    for budget in budgets { #expect(run(budget: budget) == plain, "budget \(budget)") }
  }

  // MARK: tab views

  /// Two tabs declare tags that read the same ("1", a string, and 1, an integer); the later one in render order is the
  /// one a click on that tag selects, and it is a string, which the string selection accepts. The earlier one is deep,
  /// so when staged it registers after the later one.
  private struct DuplicateTags: View {
    @State var selection = "0"
    let log: Log
    var body: some View {
      TabView(selection: $selection) {
        AnyView(Deep(depth: 13)).tag(1).tabItem { Text("first") }
        Text("second").tag("1").tabItem { Text("second") }
        AnyView(Deep(depth: 11)).tag("2").tabItem { Text("third") }
      }
      .onChange(of: selection) { log.picked.append(selection) }
    }
  }

  private final class Log {
    var selections: [Int] = []
    var picked: [String] = []
    var bodies = 0
  }

  @Test
  func tagsUnderATabViewRegisterInTheOrderOfPlainRecursion() {
    func run(budget: Int) -> (tree: [String], selections: [String]) {
      withBudget(budget) {
        let log = Log()
        let tree = FiberTree(DuplicateTags(log: log), deferLazyCollections: false)
        defer { tree._dispose() }
        let first = dump(tree)
        for value in ["2", "1"] {
          guard let button = find(tree.root, where: { $0.attributes["role"] == "tab" && $0.attributes["data-tab-value"] == value }) else {
            Issue.record("missing tab \(value)")
            continue
          }
          tree.dispatch(event: "click", at: button.identity)
          _ = tree.renderNode
        }
        return (first, log.picked)
      }
    }
    let plain = run(budget: 0)
    #expect(plain.selections == ["2", "1"])
    for budget in budgets {
      let staged = run(budget: budget)
      #expect(staged.tree == plain.tree, "budget \(budget): tree")
      #expect(staged.selections == plain.selections, "budget \(budget): selections")
    }
  }

  private struct TabsInTabs: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        Text("inner tab")
      } else {
        TabView {
          Tab("tab \(depth)", systemImage: "circle") { AnyView(TabsInTabs(depth: depth - 1)).padding(1) }
          Tab("other \(depth)", systemImage: "square") { Text("other panel \(depth)") }
        }
      }
    }
  }

  @Test
  func tabViewsInsideTabViewsComeOutAsWithPlainRecursion() {
    func tree(budget: Int) -> [String] {
      withBudget(budget) {
        let tree = FiberTree(TabsInTabs(depth: 5), deferLazyCollections: false)
        defer { tree._dispose() }
        return dump(tree)
      }
    }
    let plain = tree(budget: 0)
    #expect(plain.contains { $0.contains("inner tab") })
    for budget in budgets { #expect(tree(budget: budget) == plain, "budget \(budget)") }
  }

  // MARK: pickers

  private struct Pickers: View {
    @State var menu = 2
    @State var segmented = "b"
    let log: Log
    var body: some View {
      VStack {
        Picker("menu", selection: $menu) {
          AnyView(Deep(depth: 12)).tag(1)
          Text("two").tag(2)
          Text("three").tag(3)
        }
        Picker("segments", selection: $segmented) {
          AnyView(Deep(depth: 13)).tag("a")
          Text("b").tag("b")
          Text("c").tag("c")
        }
        .pickerStyle(.segmented)
        Form {
          Picker("grouped", selection: $menu) {
            Text("one").tag(1)
            AnyView(Deep(depth: 10)).tag(2)
          }
        }
        Text("menu \(menu) segmented \(segmented)")
      }
    }
  }

  @Test
  func pickersBuildTheirOptionsAsWithPlainRecursion() {
    func run(budget: Int) -> (tree: [String], afterChanges: [String]) {
      withBudget(budget) {
        let tree = FiberTree(Pickers(log: Log()), deferLazyCollections: false)
        defer { tree._dispose() }
        let first = dump(tree)
        // Change the menu picker through its select, then press a segment.
        if let select = find(tree.root, where: { $0.kind == .element("select") }),
           let option = select.renderNode.children.last, let value = option.attributes["value"] {
          tree.dispatch(event: "change", value: value, at: select.identity)
          _ = tree.renderNode
        } else {
          Issue.record("missing select")
        }
        if let segment = find(tree.root, where: { $0.attributes["role"] == "radio" && $0.attributes["aria-checked"] == "false" }) {
          tree.dispatch(event: "click", at: segment.identity)
          _ = tree.renderNode
        } else {
          Issue.record("missing segment")
        }
        return (first, dump(tree))
      }
    }
    let plain = run(budget: 0)
    #expect(plain.tree.contains { $0.contains("segmented-picker") })
    #expect(plain.afterChanges != plain.tree)
    for budget in budgets {
      let staged = run(budget: budget)
      #expect(staged.tree == plain.tree, "budget \(budget): tree")
      #expect(staged.afterChanges == plain.afterChanges, "budget \(budget): after changes")
    }
  }

  // MARK: equatable views

  private struct Counted: View, Equatable {
    let value: Int
    let reads: Bool
    let log: Log
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value && lhs.reads == rhs.reads }
    var body: some View {
      log.bodies += 1
      return AnyView(Deep(depth: 9)).opacity(0.9).overlay(Text("value \(value)"))
    }
  }

  private struct StateInside: View, Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
    @State private var count = 0
    var body: some View {
      AnyView(Deep(depth: 8)).padding(1).overlay(Button("bump") { count += 1 }).overlay(Text("count \(count)"))
    }
  }

  private struct EquatableRoot: View {
    @State var tick = 0
    let log: Log
    var body: some View {
      VStack {
        Counted(value: 1, reads: false, log: log).equatable()
        // A sibling that reads state does not stop the one above from being reused.
        Text("tick \(tick)")
        StateInside().equatable()
        Button("tick") { tick += 1 }
      }
    }
  }

  @Test
  func equatableViewsSkipTheirBodyAsWithPlainRecursion() {
    let savedReuse = _EquatableViewReuse.enabled
    _EquatableViewReuse.enabled = true
    defer { _EquatableViewReuse.enabled = savedReuse }
    func run(budget: Int) -> (bodies: Int, tree: [String]) {
      withBudget(budget) {
        let log = Log()
        let tree = FiberTree(EquatableRoot(log: log), deferLazyCollections: false)
        defer { tree._dispose() }
        for label in ["tick", "bump", "tick", "bump"] {
          guard let fiber = clickable(tree, label) else {
            Issue.record("missing \(label)")
            continue
          }
          tree.dispatch(event: "click", at: fiber.identity)
          _ = tree.renderNode
        }
        return (log.bodies, dump(tree))
      }
    }
    let plain = run(budget: 0)
    #expect(plain.bodies >= 1)
    for budget in budgets {
      let staged = run(budget: budget)
      #expect(staged.bodies == plain.bodies, "budget \(budget): bodies")
      #expect(staged.tree == plain.tree, "budget \(budget): tree")
    }
  }

  // MARK: the graveyard for closures

  @Test
  func aLongChainOfObjectsHoldingEachOtherThroughClosuresIsFreedFromALoop() {
    let graveyard = _ClosureGraveyard()
    final class Holder {
      var action: () -> Void = {}
      let graveyard: _ClosureGraveyard
      init(_ graveyard: _ClosureGraveyard, previous: Holder?) {
        self.graveyard = graveyard
        if let previous { action = { _ = previous } }
      }
      deinit { graveyard.bury(&action) }
    }
    var last: Holder? = Holder(graveyard, previous: nil)
    for _ in 0..<300_000 { last = Holder(graveyard, previous: last) }
    last = nil
    #expect(last == nil)
  }
}
