import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// Beyond `_RenderStaging.budget`, an erased view boundary hands its render to the loop that drives the pass and
/// returns a node that stands in for it (`_PendingRender`); modifiers that only write to their node wait for it.
/// These tests turn staging on and compare what comes out with plain recursion, and measure how deep the recursion
/// goes (how far down the call stack the leaf of a chain renders).
@Suite(.serialized)
@MainActor
struct RenderCutsTests {
  private final class Log {
    var appears: [String] = []
    var preferences: [[Int]] = []
    var tapTints: [String] = []
    var gestureTints: [String] = []
  }

  private struct OrderKey: PreferenceKey {
    static let defaultValue: [Int] = []
    static func reduce(value: inout [Int], nextValue: () -> [Int]) { value.append(contentsOf: nextValue()) }
  }

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

  private struct Result {
    var stackBytes: UInt
    /// How far down the stack the stages of staged containers ran (0 when none did).
    var stageStackBytes: UInt = 0
    var tree: [String]
    var nodeJobs: Int
    var forced: Int
  }

  private func render<V: View>(budget: Int, _ make: () -> V) -> Result {
    withBudget(budget) {
      let jobs = _RenderStaging.nodeJobsCreated
      let forced = _RenderStaging.nodeJobsForced
      var marker = 0
      let base = withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
      RenderCutsProbe.lowest = base
      RenderCutsProbe.lowestStage = .max
      _RenderStaging.stageProbe = {
        var marker = 0
        let address = withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
        RenderCutsProbe.lowestStage = min(RenderCutsProbe.lowestStage, address)
      }
      defer { _RenderStaging.stageProbe = nil }
      let tree = FiberTree(make(), deferLazyCollections: false)
      defer { tree._dispose() }
      return Result(
        stackBytes: base - RenderCutsProbe.lowest,
        stageStackBytes: RenderCutsProbe.lowestStage == .max ? 0 : base - RenderCutsProbe.lowestStage,
        tree: dump(tree),
        nodeJobs: _RenderStaging.nodeJobsCreated - jobs, forced: _RenderStaging.nodeJobsForced - forced)
    }
  }

  // MARK: chains

  /// The leaf of the chains: records how far down the call stack it renders.
  fileprivate struct ProbeLeaf: View {
    typealias Body = Never
    @MainActor func _render(in context: _RenderContext) -> _RenderNode {
      var marker = 0
      let address = withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
      RenderCutsProbe.lowest = min(RenderCutsProbe.lowest, address)
      return .text("leaf")
    }
  }

  private struct ModifierChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        AnyView(ModifierChain(depth: depth - 1))
          .opacity(0.99)
          .padding(1)
          .foregroundColor(.red)
          .id(depth)
          .background(Color.blue)
          .accessibilityLabel("level \(depth)")
      }
    }
  }

  private struct ConditionalChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else if depth % 2 == 0 {
        ConditionalChain(depth: depth - 1)
      } else {
        ConditionalChain(depth: depth - 1).padding(2)
      }
    }
  }

  @Test
  func aChainOfModifiersRendersWithAShallowRecursion() {
    let plain = render(budget: 0) { ModifierChain(depth: 120) }
    #expect(plain.nodeJobs == 0)
    for budget in [2, 5, 12] {
      let staged = render(budget: budget) { ModifierChain(depth: 120) }
      print("METRIC chain budget \(budget): stack \(staged.stackBytes) vs \(plain.stackBytes), jobs \(staged.nodeJobs), forced \(staged.forced), lines \(staged.tree.count)")
      #expect(staged.nodeJobs > 0, "budget \(budget)")
      #expect(staged.tree == plain.tree, "budget \(budget): the tree differs")
      #expect(staged.stackBytes < plain.stackBytes / 4, "budget \(budget): stack \(staged.stackBytes) vs \(plain.stackBytes) bytes")
    }
  }

  @Test
  func aChainOfConditionalsRendersWithAShallowRecursion() {
    let plain = render(budget: 0) { ConditionalChain(depth: 120) }
    for budget in [2, 5, 12] {
      let staged = render(budget: budget) { ConditionalChain(depth: 120) }
      #expect(staged.nodeJobs > 0, "budget \(budget)")
      #expect(staged.tree == plain.tree, "budget \(budget): the tree differs")
      #expect(staged.stackBytes < plain.stackBytes / 4, "budget \(budget): stack \(staged.stackBytes) vs \(plain.stackBytes) bytes")
    }
  }

  // MARK: containers

  private struct HStackChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        HStack {
          Text("h\(depth)")
          if depth % 3 == 0 { Spacer() }
          AnyView(HStackChain(depth: depth - 1))
        }
        .padding(1)
      }
    }
  }

  private struct ScrollChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        ScrollView { AnyView(ScrollChain(depth: depth - 1)) }.padding(1)
      }
    }
  }

  private struct ListChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        List { AnyView(ListChain(depth: depth - 1)) }
      }
    }
  }

  private struct GridChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else if depth % 2 == 0 {
        Grid { GridRow { AnyView(GridChain(depth: depth - 1)) } }
      } else {
        LazyVGrid(columns: [GridItem(.flexible())]) { AnyView(GridChain(depth: depth - 1)) }
      }
    }
  }

  private struct MixedChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        switch depth % 5 {
        case 0: HStack { Spacer(); AnyView(MixedChain(depth: depth - 1)) }
        case 1: ScrollView(.horizontal) { MixedChain(depth: depth - 1).padding(2).opacity(0.5) }
        case 2: VStack { MixedChain(depth: depth - 1) }.frame(width: 300)
        case 3: ZStack { MixedChain(depth: depth - 1) }.background(Color.green)
        default: MixedChain(depth: depth - 1).foregroundColor(.blue).id(depth)
        }
      }
    }
  }

  private func checkChain<V: View>(_ name: String, budgets: [Int] = [2, 5, 12], _ make: () -> V, file: StaticString = #file) {
    let plain = render(budget: 0, make)
    #expect(plain.nodeJobs == 0)
    for budget in budgets {
      let staged = render(budget: budget, make)
      print("METRIC \(name) budget \(budget): stack \(staged.stackBytes) vs \(plain.stackBytes), nodeJobs \(staged.nodeJobs), forced \(staged.forced)")
      #expect(staged.tree == plain.tree, "\(name) budget \(budget): the tree differs")
      #expect(staged.stackBytes < plain.stackBytes / 4, "\(name) budget \(budget): stack \(staged.stackBytes) vs \(plain.stackBytes) bytes")
      // The stages of staged containers run from the loop, innermost first, not one inside another.
      // (Only where stages nest: a single container's stage runs near the top of the stack either way.)
      if plain.stageStackBytes > 100_000 {
        #expect(staged.stageStackBytes < plain.stageStackBytes / 4, "\(name) budget \(budget): stages at \(staged.stageStackBytes) vs \(plain.stageStackBytes) bytes")
      }
    }
  }

  @Test func nestedHStacksRenderWithAShallowRecursion() { checkChain("hstack") { HStackChain(depth: 90) } }
  @Test func nestedScrollViewsRenderWithAShallowRecursion() { checkChain("scroll") { ScrollChain(depth: 90) } }
  @Test func nestedListsRenderWithAShallowRecursion() { checkChain("list") { ListChain(depth: 60) } }
  @Test func nestedGridsRenderWithAShallowRecursion() { checkChain("grid") { GridChain(depth: 90) } }
  @Test func aMixOfContainersAndModifiersRendersWithAShallowRecursion() { checkChain("mixed") { MixedChain(depth: 150) } }

  // MARK: behaviour of the pending nodes

  /// One level: a counter, a button and a preference write in overlays, an environment change, a lifecycle callback
  /// and the next level, nested through modifiers only. `eager` adds a modifier that is applied in render order.
  private struct Level: View {
    let depth: Int
    let log: Log
    var eager = false
    @State private var taps = 0
    @Environment(\.cutsTint) private var tint

    var body: some View {
      if depth == 0 {
        Text("leaf \(tint)")
          .onAppear { log.appears.append("leaf") }
          .preference(key: OrderKey.self, value: [0])
      } else if eager && depth % 4 == 0 {
        AnyView(Level(depth: depth - 1, log: log, eager: eager))
          .environment(\.cutsTint, depth == 7 ? "seven" : tint)
          .overlay(Button("tap\(depth)") { taps += 1; log.tapTints.append("\(depth):\(tint)") })
          .overlay(Text("L\(depth) taps \(taps) tint \(tint)").preference(key: OrderKey.self, value: [depth * 10]))
          .onChange(of: taps) {}
          .onAppear { log.appears.append("L\(depth)") }
      } else {
        AnyView(Level(depth: depth - 1, log: log, eager: eager))
          .environment(\.cutsTint, depth == 7 ? "seven" : tint)
          .overlay(Button("tap\(depth)") { taps += 1; log.tapTints.append("\(depth):\(tint)") })
          .overlay(Text("L\(depth) taps \(taps) tint \(tint)").preference(key: OrderKey.self, value: [depth * 10]))
          .onTapGesture { log.gestureTints.append("\(depth):\(tint)") }
          .accessibilityIdentifier("tg\(depth)")
          .padding(1)
          .onAppear { log.appears.append("L\(depth)") }
          .id(depth)
      }
    }
  }

  private struct Root: View {
    let depth: Int
    let log: Log
    var eager = false
    var body: some View {
      Level(depth: depth, log: log, eager: eager)
        .onPreferenceChange(OrderKey.self) { log.preferences.append($0) }
    }
  }

  private func clickAll(_ tree: FiberTree, _ labels: [String]) {
    for label in labels {
      guard let fiber = find(tree.root, label) else { Issue.record("missing \(label)"); continue }
      tree.dispatch(event: "click", at: fiber.identity)
      _ = tree.renderNode
    }
  }

  private func find(_ fiber: Fiber, _ label: String) -> Fiber? {
    var stack = [fiber]
    while let current = stack.popLast() {
      if label.hasPrefix("tg"), current.renderNode.attributes["data-testid"] == label { return current }
      if current.renderNode.attributes["data-control-kind"] == "button", texts(current.renderNode) == [label] { return current }
      stack.append(contentsOf: current.children.reversed())
    }
    return nil
  }

  private func texts(_ node: _RenderNode) -> [String] {
    var found: [String] = []
    var stack = [node]
    while let current = stack.popLast() {
      if current.kind == .text, let text = current.text { found.append(text) }
      stack.append(contentsOf: current.children.reversed())
    }
    return found
  }

  private func run(budget: Int, depth: Int = 24, eager: Bool = false) -> (tree: [String], afterClicks: [String], log: Log, nodeJobs: Int) {
    withBudget(budget) {
      let log = Log()
      let before = _RenderStaging.nodeJobsCreated
      let tree = FiberTree(Root(depth: depth, log: log, eager: eager), deferLazyCollections: false)
      defer { tree._dispose() }
      let first = dump(tree)
      clickAll(tree, ["tap\(depth)", "tap\(depth - 1)", "tap\(depth - 1)", "tap7", "tap1", "tap7", "tg7", "tg6", "tg21"])
      return (first, dump(tree), log, _RenderStaging.nodeJobsCreated - before)
    }
  }

  @Test
  func theTreeComesOutAsWithPlainRecursion() {
    for eager in [false, true] {
      let plain = run(budget: 0, eager: eager)
      #expect(plain.nodeJobs == 0)
      for budget in [1, 2, 5, 12] {
        let staged = run(budget: budget, eager: eager)
        #expect(staged.nodeJobs > 0, "budget \(budget) should have deferred something")
        #expect(staged.tree == plain.tree, "eager \(eager), budget \(budget): first render differs")
        #expect(staged.afterClicks == plain.afterClicks, "eager \(eager), budget \(budget): render after clicks differs")
      }
    }
  }

  @Test
  func stateKeepsItsIdentityAcrossPendingNodes() {
    for eager in [false, true] {
      let staged = run(budget: 2, eager: eager)
      #expect(staged.afterClicks.contains { $0.contains("L24 taps 1") })
      #expect(staged.afterClicks.contains { $0.contains("L23 taps 2") })
      #expect(staged.afterClicks.contains { $0.contains("L7 taps 2") })
      #expect(staged.afterClicks.contains { $0.contains("L1 taps 1") })
    }
  }

  /// A handler reads the environment installed when it was created, which for a modifier applied later is the one
  /// the modifier was rendered in.
  @Test
  func handlersCreatedLaterSeeTheEnvironmentOfTheirView() {
    let plain = run(budget: 0)
    #expect(plain.log.tapTints.contains("7:none") && plain.log.tapTints.contains("1:seven"))
    #expect(plain.log.gestureTints.contains("7:none") && plain.log.gestureTints.contains("6:seven"))
    for budget in [1, 2, 5] {
      let staged = run(budget: budget)
      #expect(staged.log.tapTints == plain.log.tapTints, "budget \(budget)")
      #expect(staged.log.gestureTints == plain.log.gestureTints, "budget \(budget)")
    }
  }

  @Test
  func lifecycleCallbacksRunOncePerViewAsWithPlainRecursion() {
    for eager in [false, true] {
      let plain = run(budget: 0, eager: eager)
      let staged = run(budget: 2, eager: eager)
      #expect(staged.log.appears.sorted() == plain.log.appears.sorted())
      #expect(Set(staged.log.appears).count == staged.log.appears.count)
      #expect(staged.log.appears.contains("leaf") && staged.log.appears.contains("L24"))
    }
  }

  @Test
  func preferencesReduceInTheOrderOfPlainRecursion() {
    for eager in [false, true] {
      let plain = run(budget: 0, eager: eager)
      #expect(!plain.log.preferences.isEmpty)
      for budget in [1, 2, 3, 7] {
        let staged = run(budget: budget, eager: eager)
        #expect(staged.log.preferences == plain.log.preferences, "eager \(eager), budget \(budget): preference order differs")
      }
    }
  }

  @Test
  func environmentChangesReachPendingContent() {
    for eager in [false, true] {
      let staged = run(budget: 2, eager: eager)
      // Level 7 sets the tint for everything below it; the levels above keep the default.
      #expect(staged.tree.contains { $0.contains("L8 taps 0 tint none") })
      #expect(staged.tree.contains { $0.contains("L6 taps 0 tint seven") })
      #expect(staged.tree.contains { $0.contains("leaf seven") })
    }
  }

  @Test
  func aLongChainOfLevelsComesOutAsWithPlainRecursion() {
    let staged = run(budget: 3, depth: 60)
    let plain = run(budget: 0, depth: 60)
    #expect(staged.tree == plain.tree)
  }

  private struct ToolbarLevel: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        Text("bottom").toolbar { Text("deep toolbar") }
      } else {
        AnyView(ToolbarLevel(depth: depth - 1)).opacity(0.5).padding(1)
      }
    }
  }

  /// A navigation stack collects the toolbars its content declares while it renders, and only while it does; the
  /// ones declared in nodes that were pending must be collected too, and land where they do without staging.
  @Test
  func aNavigationStackCollectsToolbarsDeclaredInPendingContent() {
    func render(budget: Int) -> (lines: [String], jobs: Int) {
      withBudget(budget) {
        let before = _RenderStaging.nodeJobsCreated
        let tree = FiberTree(NavigationStack { ToolbarLevel(depth: 12) }, deferLazyCollections: false)
        defer { tree._dispose() }
        return (dump(tree), _RenderStaging.nodeJobsCreated - before)
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
  /// `Counter`'s body reads, which happens in a node that was pending.
  private struct ReadsStateInPendingContent: Equatable, View {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
    var body: some View { AnyView(Counter()).opacity(0.5).padding(1) }
  }

  @Test
  func equatableViewSeesWhatPendingContentReads() {
    let savedReuse = _EquatableViewReuse.enabled
    _EquatableViewReuse.enabled = true
    defer { _EquatableViewReuse.enabled = savedReuse }
    func run(budget: Int) -> [String] {
      withBudget(budget) {
        let tree = FiberTree(ReadsStateInPendingContent().equatable(), deferLazyCollections: false)
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
  func readingAPendingNodeRendersItOnTheSpot() {
    withBudget(1) {
      let log = Log()
      let tree = FiberTree(Root(depth: 6, log: log), deferLazyCollections: false, startLifecycle: false)
      defer { tree._dispose() }
      #expect(texts(tree.renderNode).contains("leaf none"))
    }
  }

  @Test
  func hstackAndListAttributesDependOnTheirContent() {
    // `HStack` marks itself flexible when a `Spacer` is among its children, `List` lazy when a lazy collection is.
    // Both are set when the content has rendered, so they must come out as without staging however deep they are.
    func marks(budget: Int) -> [String] {
      withBudget(budget) {
        let tree = FiberTree(HStackChain(depth: 30), deferLazyCollections: false)
        defer { tree._dispose() }
        return dump(tree).filter { $0.contains("data-flexible-width") }
      }
    }
    let plain = marks(budget: 0)
    #expect(plain.count == 10)
    #expect(marks(budget: 2) == plain)
    #expect(marks(budget: 1) == plain)
  }

  // MARK: modifiers that used to need their node at once

  /// What the callbacks of the modifiers observe in render order record: `onChange`, `onPreferenceChange`, a
  /// presentation's `onDismiss`.
  private final class Order {
    var changes: [String] = []
    var readers: [String] = []
    var dismissals: [String] = []
  }

  private struct ListKey: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) { value.append(contentsOf: nextValue()) }
  }

  private struct TitledModifier: ViewModifier {
    let level: Int
    func body(content: Content) -> some View {
      content.padding(1).opacity(0.99).accessibilityLabel("custom \(level)")
    }
  }

  private struct ForcingChain: View {
    enum Kind { case onChange, preference, sheet, navigation, animation, custom, mixed }
    let kind: Kind
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        let next = AnyView(ForcingChain(kind: kind, depth: depth - 1))
        switch kind == .mixed ? [Kind.onChange, .preference, .sheet, .navigation, .animation, .custom][depth % 6] : kind {
        case .onChange: next.onChange(of: depth) {}
        case .preference: next.preference(key: ListKey.self, value: ["\(depth)"]).onPreferenceChange(ListKey.self) { _ in }
        case .sheet: next.sheet(isPresented: .constant(false)) { Text("sheet \(depth)") }
        case .navigation: next.navigationTitle("level \(depth)").navigationDestination(for: Int.self) { Text("to \($0)") }.toolbar { Text("bar \(depth)") }
        case .animation: next.animation(.easeInOut, value: depth)
        case .custom: next.modifier(TitledModifier(level: depth))
        case .mixed: next
        }
      }
    }
  }

  @Test func aChainOfOnChangeRendersWithAShallowRecursion() { checkChain("onChange") { ForcingChain(kind: .onChange, depth: 120) } }
  @Test func aChainOfPreferencesRendersWithAShallowRecursion() { checkChain("preference") { ForcingChain(kind: .preference, depth: 120) } }
  @Test func aChainOfSheetsRendersWithAShallowRecursion() { checkChain("sheet") { ForcingChain(kind: .sheet, depth: 120) } }
  @Test func aChainOfNavigationModifiersRendersWithAShallowRecursion() {
    checkChain("navigation") { NavigationStack { ForcingChain(kind: .navigation, depth: 90) } }
  }
  @Test func aChainOfAnimationsRendersWithAShallowRecursion() { checkChain("animation") { ForcingChain(kind: .animation, depth: 120) } }
  @Test func aChainOfCustomModifiersRendersWithAShallowRecursion() { checkChain("custom") { ForcingChain(kind: .custom, depth: 120) } }
  @Test func aMixedChainRendersWithAShallowRecursion() { checkChain("forcing") { NavigationStack { ForcingChain(kind: .mixed, depth: 120) } } }

  private struct ContainerChain: View {
    enum Kind { case form, section, disclosure, groupBox, labeled, menu, controlGroup }
    let kind: Kind
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        let next = AnyView(ContainerChain(kind: kind, depth: depth - 1))
        switch kind {
        case .form: Form { next }
        case .section: Section("s\(depth)") { next }
        case .disclosure: DisclosureGroup("d\(depth)") { next }
        case .groupBox: GroupBox("g\(depth)") { next }
        case .labeled: LabeledContent("l\(depth)") { next }
        case .menu: Menu("m\(depth)") { next }
        case .controlGroup: ControlGroup("c\(depth)") { next }
        }
      }
    }
  }

  @Test func nestedFormsRenderWithAShallowRecursion() { checkChain("form") { ContainerChain(kind: .form, depth: 60) } }
  @Test func nestedSectionsRenderWithAShallowRecursion() { checkChain("section") { ContainerChain(kind: .section, depth: 60) } }
  @Test func nestedDisclosureGroupsRenderWithAShallowRecursion() { checkChain("disclosure") { ContainerChain(kind: .disclosure, depth: 90) } }
  @Test func nestedGroupBoxesRenderWithAShallowRecursion() { checkChain("groupbox") { ContainerChain(kind: .groupBox, depth: 90) } }
  @Test func nestedLabeledContentRendersWithAShallowRecursion() { checkChain("labeled") { ContainerChain(kind: .labeled, depth: 90) } }
  @Test func nestedControlGroupsRenderWithAShallowRecursion() { checkChain("controlgroup") { ContainerChain(kind: .controlGroup, depth: 90) } }
  @Test func nestedMenusRenderWithAShallowRecursion() { checkChain("menu") { ContainerChain(kind: .menu, depth: 90) } }

  /// Empty content decides what a `Form` and a `GroupBox` hold, so it has to come out the same when it is deferred.
  @Test func containersWithEmptyContentComeOutAsWithPlainRecursion() {
    func tree(budget: Int) -> [String] {
      withBudget(budget) {
        let tree = FiberTree(VStack {
          Form { EmptyView() }
          GroupBox("empty") { EmptyView() }
          Section("empty") { EmptyView() }
          DisclosureGroup("empty") { EmptyView() }
          LabeledContent("empty") { EmptyView() }
          Menu("empty") { EmptyView() }
          Form { AnyView(Text("full")) }
          Section("full") { Text("a"); Text("b") }
        }, deferLazyCollections: false)
        defer { tree._dispose() }
        return dump(tree)
      }
    }
    let plain = tree(budget: 0)
    for budget in [1, 2, 3] { #expect(tree(budget: budget) == plain, "budget \(budget)") }
  }

  /// A modifier on a `Group`, `ForEach` or tuple applies to each child; with a child that has not rendered it waits
  /// for it instead of rendering it on the spot.
  private struct FragmentChain: View {
    enum Kind { case single, several, forEach, tuple }
    let kind: Kind
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        let next = AnyView(FragmentChain(kind: kind, depth: depth - 1))
        switch kind {
        case .single: Group { next }.opacity(0.99).padding(1)
        case .several: Group { Text("g\(depth)"); next }.opacity(0.99).background(Color.red)
        case .forEach: ForEach([depth], id: \.self) { _ in next }.padding(2)
        case .tuple: Group { next; Text("t\(depth)") }.onTapGesture {}
        }
      }
    }
  }

  @Test func groupsUnderModifiersRenderWithAShallowRecursion() { checkChain("group") { FragmentChain(kind: .single, depth: 90) } }
  @Test func severalChildrenUnderModifiersRenderWithAShallowRecursion() { checkChain("groups") { FragmentChain(kind: .several, depth: 90) } }
  @Test func aForEachUnderModifiersRendersWithAShallowRecursion() { checkChain("foreach") { FragmentChain(kind: .forEach, depth: 90) } }
  @Test func aTupleUnderModifiersRendersWithAShallowRecursion() { checkChain("tuple") { FragmentChain(kind: .tuple, depth: 90) } }

  /// A stack above a chain of modifiers gets a child that has not rendered, and keeps it for the loop (as a job of its
  /// own, besides the jobs of the chain) instead of looking at it, to drop it if it is empty, from the stack's frames.
  @Test
  func aStackKeepsAPendingChildInsteadOfRenderingItOnTheSpot() {
    func run(budget: Int) -> (tree: [String], containerJobs: Int) {
      withBudget(budget) {
        let created = _RenderStaging.jobsCreated, nodes = _RenderStaging.nodeJobsCreated
        let tree = FiberTree(VStack { ModifierChain(depth: 40) }, deferLazyCollections: false)
        defer { tree._dispose() }
        return (dump(tree), (_RenderStaging.jobsCreated - created) - (_RenderStaging.nodeJobsCreated - nodes))
      }
    }
    let plain = run(budget: 0)
    #expect(plain.containerJobs == 0)
    for budget in [3, 6] {
      let staged = run(budget: budget)
      #expect(staged.tree == plain.tree, "budget \(budget)")
      #expect(staged.containerJobs > 0, "budget \(budget): the stack looked at its child")
    }
  }

  private struct TabsRoot: View {
    @State private var selected = "Home"
    @State private var optional: String? = nil
    var body: some View {
      VStack {
        TabView(selection: $selected) {
          Text("Home tab").tag("Home").tabItem { Label("Home", systemImage: "house") }
          Text("Settings tab").tag("Settings").tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(height: 90)
        TabView(selection: $optional) {
          Tab("Alpha", systemImage: "a.circle", value: "alpha") { Text("Alpha panel") }
          Tab("Beta", systemImage: "b.circle", value: "beta") { Text("Beta panel") }
        }
        .frame(height: 90)
      }
    }
  }

  @Test
  func tabViewsComeOutAsWithPlainRecursion() {
    func tree(budget: Int) -> [String] {
      withBudget(budget) {
        let tree = FiberTree(TabsRoot(), deferLazyCollections: false)
        defer { tree._dispose() }
        return dump(tree)
      }
    }
    let plain = tree(budget: 0)
    #expect(plain.contains { $0.contains("data-tab-label") || $0.contains("tab-panel") })
    for budget in [1, 2, 3, 12] { #expect(tree(budget: budget) == plain, "budget \(budget)") }
  }

  private struct Nest: View {
    let depth: Int
    var body: some View {
      if depth == 0 { TabsRoot() } else { Nest(depth: depth - 1).padding(1) }
    }
  }

  /// The tabs sit at every depth relative to the budget.
  @Test
  func tabViewsAtEveryDepthComeOutAsWithPlainRecursion() {
    func tree(budget: Int, depth: Int) -> [String] {
      withBudget(budget) {
        let tree = FiberTree(Nest(depth: depth), deferLazyCollections: false)
        defer { tree._dispose() }
        return dump(tree)
      }
    }
    for depth in 0..<16 {
      let plain = tree(budget: 0, depth: depth)
      for budget in [3, 6, 12] { #expect(tree(budget: budget, depth: depth) == plain, "nesting \(depth), budget \(budget)") }
    }
  }

  private struct PreviewModifier: ViewModifier {
    func body(content: Content) -> some View { VStack(alignment: .leading, spacing: 0) { content } }
  }

  private struct Card<Content: View>: View {
    let content: Content
    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("title")
        VStack(alignment: .leading, spacing: 14) { content }
          .frame(maxWidth: .infinity, alignment: .leading)
          .modifier(PreviewModifier())
      }
    }
  }

  private struct CardNest: View {
    let depth: Int
    var body: some View {
      if depth == 0 { Card(content: TabsRoot()) } else { AnyView(CardNest(depth: depth - 1)).padding(1) }
    }
  }

  /// A tab view collects what it holds, and so runs every pending job, from inside a render that a stack above it (the
  /// card, the preview modifier) is waiting for to settle: the stack must not look at that render before it is done, or
  /// it drops it as empty. Whether that happens depends on where the budget falls, so every depth is tried.
  @Test
  func aStackAboveATabViewKeepsItsContent() {
    func tree(budget: Int, depth: Int) -> [String] {
      withBudget(budget) {
        let tree = FiberTree(CardNest(depth: depth), deferLazyCollections: false)
        defer { tree._dispose() }
        return dump(tree)
      }
    }
    var bad: [String] = []
    for depth in 0..<16 {
      let plain = tree(budget: 0, depth: depth)
      #expect(plain.contains { $0.contains("tab-panel") || $0.contains("Alpha panel") })
      for budget in 1...14 where tree(budget: budget, depth: depth) != plain { bad.append("depth \(depth) budget \(budget)") }
    }
    #expect(bad.isEmpty, "\(bad)")
  }

  // MARK: callbacks the application observes in render order

  /// A branch whose levels each register a callback. The branch is deep, so staging keeps part of it for later,
  /// while the siblings around it register theirs at once.
  private struct ChangeBranch: View {
    let name: String
    let depth: Int
    let order: Order
    var body: some View {
      if depth == 0 {
        Text("leaf").onChange(of: 0, initial: true) { order.changes.append("\(name)0") }
      } else {
        AnyView(ChangeBranch(name: name, depth: depth - 1, order: order))
          .onChange(of: depth, initial: true) { order.changes.append("\(name)\(depth)") }
      }
    }
  }

  private struct ChangeTree: View {
    let order: Order
    var body: some View {
      VStack {
        ChangeBranch(name: "A", depth: 6, order: order)
        Text("b").onChange(of: 1, initial: true) { order.changes.append("B") }
        ChangeBranch(name: "C", depth: 6, order: order)
        Text("d").onChange(of: 1, initial: true) { order.changes.append("D") }
      }
    }
  }

  @Test
  func onChangeCallbacksFireInTheOrderOfPlainRecursion() {
    func run(budget: Int) -> [String] {
      withBudget(budget) {
        let order = Order()
        let tree = FiberTree(ChangeTree(order: order), deferLazyCollections: false)
        defer { tree._dispose() }
        _ = tree.renderNode
        return order.changes
      }
    }
    let plain = run(budget: 0)
    #expect(plain.first == "A0" && plain.count == 16, "\(plain)")
    for budget in [1, 2, 3, 5] { #expect(run(budget: budget) == plain, "budget \(budget)") }
  }

  private struct ReaderBranch: View {
    let name: String
    let depth: Int
    let order: Order
    var body: some View {
      if depth == 0 {
        Text("leaf").preference(key: ListKey.self, value: ["\(name)0"])
      } else {
        AnyView(ReaderBranch(name: name, depth: depth - 1, order: order))
          .preference(key: ListKey.self, value: ["\(name)\(depth)"])
          .onPreferenceChange(ListKey.self) { order.readers.append("\(name)\(depth): \($0.joined(separator: ","))") }
      }
    }
  }

  private struct ReaderTree: View {
    let order: Order
    var body: some View {
      VStack {
        ReaderBranch(name: "A", depth: 4, order: order)
        Text("b").preference(key: ListKey.self, value: ["B"]).onPreferenceChange(ListKey.self) { order.readers.append("B: \($0.joined(separator: ","))") }
        ReaderBranch(name: "C", depth: 4, order: order)
      }
      .onPreferenceChange(ListKey.self) { order.readers.append("root: \($0.joined(separator: ","))") }
    }
  }

  /// A reader sees the writes that come before it in render order, and the readers run in that order, wherever the
  /// parts of the tree they belong to render.
  @Test
  func preferenceReadersSeeWhatPlainRecursionShowedThem() {
    func run(budget: Int) -> [String] {
      withBudget(budget) {
        let order = Order()
        let tree = FiberTree(ReaderTree(order: order), deferLazyCollections: false)
        defer { tree._dispose() }
        _ = tree.renderNode
        return order.readers
      }
    }
    let plain = run(budget: 0)
    #expect(plain.count == 10, "\(plain)")
    #expect(plain.contains("A4: A0,A1,A2,A3,A4") && plain.contains("B: A0,A1,A2,A3,A4,B"), "\(plain)")
    for budget in [1, 2, 3, 5] { #expect(run(budget: budget) == plain, "budget \(budget)") }
  }

  private struct DismissTree: View {
    let order: Order
    @State private var open = true
    var body: some View {
      VStack {
        Button("close") { open = false }
        AnyView(AnyView(AnyView(Text("deep"))))
          .sheet(isPresented: $open, onDismiss: { order.dismissals.append("deep") }) { Text("deep sheet") }
        Text("near").sheet(isPresented: $open, onDismiss: { order.dismissals.append("near") }) { Text("near sheet") }
      }
    }
  }

  @Test
  func presentationDismissalsFireInTheOrderOfPlainRecursion() {
    func run(budget: Int) -> [String] {
      withBudget(budget) {
        let order = Order()
        let tree = FiberTree(DismissTree(order: order), deferLazyCollections: false)
        defer { tree._dispose() }
        clickAll(tree, ["close"])
        return order.dismissals
      }
    }
    let plain = run(budget: 0)
    #expect(plain == ["deep", "near"], "\(plain)")
    for budget in [1, 2, 3] { #expect(run(budget: budget) == plain, "budget \(budget)") }
  }

  private struct ToolbarOrderTree: View {
    var body: some View {
      NavigationStack {
        VStack {
          AnyView(AnyView(AnyView(Text("deep")))).toolbar { Button("first") {} }
          Text("near").toolbar { Button("second") {} }
          AnyView(AnyView(AnyView(Text("deeper")))).toolbar { Button("third") {} }
        }
      }
    }
  }

  @Test
  func toolbarsAreGatheredInTheOrderOfPlainRecursion() {
    func lines(budget: Int) -> [String] {
      withBudget(budget) {
        let tree = FiberTree(ToolbarOrderTree(), deferLazyCollections: false)
        defer { tree._dispose() }
        return dump(tree)
      }
    }
    let plain = lines(budget: 0)
    let order = plain.compactMap { line in ["first", "second", "third"].first { line.hasPrefix(" ") && line.contains("|\($0)|") } }
    #expect(order == ["first", "second", "third"], "\(plain.joined(separator: "\n"))")
    for budget in [1, 2, 3] { #expect(lines(budget: budget) == plain, "budget \(budget)") }
  }

  /// `.animation` walks everything below it; the walk has no call per level.
  @Test
  func theAnimationWalkNeedsNoStackPerLevel() {
    let root = _RenderNode.element("div")
    var tail = root
    for _ in 0..<200_000 {
      let next = _RenderNode.element("div")
      tail.children = [next]
      tail = next
    }
    tail.attributes["data-mesh-gradient"] = "true"
    tail.styles["position"] = "absolute"
    propagateMeshGradientAnimation("1s", to: root)
    propagateLayoutAnimation(to: root)
    #expect(tail.attributes["data-mesh-gradient-animation"] == "1s")
    #expect(tail.attributes["data-layout-animation"] == "true")
  }

  // MARK: containers that gather what their content registered

  private struct PickerChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        Picker("level \(depth)", selection: .constant(0)) {
          AnyView(PickerChain(depth: depth - 1)).tag(0)
          Text("other").tag(1)
        }
        .pickerStyle(.segmented)
      }
    }
  }

  private struct TabsChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        TabView { Tab("tab \(depth)", systemImage: "circle") { AnyView(TabsChain(depth: depth - 1)) } }
      }
    }
  }

  private struct TagsChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 { ProbeLeaf() } else { AnyView(TagsChain(depth: depth - 1)).tag(depth) }
    }
  }

  private struct NavChain: View {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        NavigationStack { AnyView(NavChain(depth: depth - 1)).navigationTitle("level \(depth)").toolbar { Text("bar \(depth)") } }
      }
    }
  }

  private struct EquatableChain: View, Equatable {
    let depth: Int
    var body: some View {
      if depth == 0 { ProbeLeaf() } else { EquatableChain(depth: depth - 1).equatable() }
    }
  }

  private struct ComboChain: View, Equatable {
    let depth: Int
    var body: some View {
      if depth == 0 {
        ProbeLeaf()
      } else {
        switch depth % 4 {
        case 0:
          Picker("level \(depth)", selection: .constant(0)) { AnyView(ComboChain(depth: depth - 1)).tag(0) }.pickerStyle(.segmented)
        case 1: TabView { Tab("tab \(depth)", systemImage: "circle") { AnyView(ComboChain(depth: depth - 1)) } }
        case 2: NavigationStack { AnyView(ComboChain(depth: depth - 1)) }
        default: ComboChain(depth: depth - 1).equatable()
        }
      }
    }
  }

  @Test func nestedPickersRenderWithAShallowRecursion() { checkChain("picker") { PickerChain(depth: 60) } }
  @Test func nestedTabViewsRenderWithAShallowRecursion() { checkChain("tabs") { TabsChain(depth: 60) } }
  @Test func zzDeepNav() { let r = render(budget: 12) { NavChain(depth: 2500) }; print("DEEPNAV \(r.stackBytes) \(r.tree.count)") }
  @Test func nestedNavigationStacksRenderWithAShallowRecursion() { checkChain("navigation") { NavChain(depth: 60) } }
  @Test func nestedEquatableViewsRenderWithAShallowRecursion() {
    let savedReuse = _EquatableViewReuse.enabled
    _EquatableViewReuse.enabled = true
    defer { _EquatableViewReuse.enabled = savedReuse }
    checkChain("equatable") { EquatableChain(depth: 90) }
  }
  @Test func aMixOfGatheringContainersRendersWithAShallowRecursion() {
    let savedReuse = _EquatableViewReuse.enabled
    _EquatableViewReuse.enabled = true
    defer { _EquatableViewReuse.enabled = savedReuse }
    checkChain("combo") { ComboChain(depth: 90) }
  }
  @Test func tagsUnderATabViewRenderWithAShallowRecursion() {
    checkChain("tags") { TabView(selection: .constant(60)) { TagsChain(depth: 60) } }
  }
}

extension EnvironmentValues {
  fileprivate var cutsTint: String {
    get { self[RenderCutsTintKey.self] }
    set { self[RenderCutsTintKey.self] = newValue }
  }
}

private struct RenderCutsTintKey: EnvironmentKey { static let defaultValue = "none" }

/// The lowest stack address a probe leaf saw during a render (the stack grows down).
@MainActor private enum RenderCutsProbe {
  static var lowest: UInt = .max
  static var lowestStage: UInt = .max
}

