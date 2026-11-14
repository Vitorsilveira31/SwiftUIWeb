import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) @testable import SwiftUIWebFiber

/// A view that compares its inputs (`View._comparesInputs`, written by the source lowering for an application's views)
/// is not rendered again when its parent is, as long as its inputs, the environment it reads and its own state are
/// unchanged (`AnyView._renderReusing`).
@Suite(.serialized)
@MainActor
final class ViewReuseTests {
  final class Counter { var bodies = 0 }

  private struct Row: View {
    let title: String
    let counter: Counter
    var body: some View {
      counter.bodies += 1
      return Text("row \(title)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: Row, _ rhs: Row) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.counter, rhs.counter)
    }
  }

  private struct Page: View {
    @State var tick = 0
    let title: String
    let counter: Counter
    var body: some View {
      return VStack {
        // A branch on the state makes the page render again (a text alone would be updated in place).
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        Row(title: title, counter: counter)
      }
    }
  }

  private struct Host: View {
    let page: Page
    var body: some View { VStack { page } }
  }

  private func pass(_ tree: FiberTree) { _ = tree.renderNode }

  @Test
  func aRowWhoseInputsDidNotChangeIsNotRenderedAgainWithItsParent() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let counter = Counter()
    let page = Page(title: "a", counter: counter)
    let tree = FiberTree(Host(page: page))
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    #expect(counter.bodies == 1)
    for tick in 1...5 {
      page.tick = tick
      pass(tree)
    }
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("odd 5") && html.contains("row a"), Comment(rawValue: html))
    #expect(counter.bodies == 1, "the row's body ran \(counter.bodies) times")
  }

  private struct TitledPage: View {
    @State var title = "a"
    let counter: Counter
    var body: some View {
      VStack { Row(title: title, counter: counter) }
    }
  }

  @Test
  func aRowWhoseInputChangedIsRenderedAgain() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let counter = Counter()
    let page = TitledPage(counter: counter)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    page.title = "b"
    pass(tree)
    #expect(tree.root.renderNode.htmlDescription.contains("row b"))
    #expect(counter.bodies == 2)
  }

  private struct AccentRow: View {
    let counter: Counter
    @Environment(\.reuseTestAccent) private var accent
    var body: some View {
      counter.bodies += 1
      return Text("accent \(accent)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: AccentRow, _ rhs: AccentRow) -> Bool { _swiftUIWebSame(lhs.counter, rhs.counter) }
  }

  private struct AccentPage: View {
    @State var accent = "plain"
    @State var tick = 0
    let counter: Counter
    var body: some View {
      VStack {
        // A branch on the state makes the page render again (a text alone would be updated in place).
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        VStack {
          Text("accent")
          AccentRow(counter: counter)
        }
        .environment(\.reuseTestAccent, accent)
      }
    }
  }

  @Test
  func aRowRendersAgainWhenAnEnvironmentValueItReadChangesAndOnlyThen() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let counter = Counter()
    let page = AccentPage(counter: counter)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    page.tick = 1
    pass(tree)
    #expect(counter.bodies == 1, "an unrelated change rendered the row again")
    page.accent = "bold"
    pass(tree)
    #expect(tree.root.renderNode.htmlDescription.contains("accent bold"))
    #expect(counter.bodies == 2)
  }

  private struct StatefulRow: View {
    let counter: Counter
    @State var taps = 0
    var body: some View {
      counter.bodies += 1
      return Text("taps \(taps)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: StatefulRow, _ rhs: StatefulRow) -> Bool { _swiftUIWebSame(lhs.counter, rhs.counter) }
  }

  private struct StatefulPage: View {
    @State var tick = 0
    let row: StatefulRow
    var body: some View {
      VStack {
        // A branch on the state makes the page render again (a text alone would be updated in place).
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        row
      }
    }
  }

  @Test
  func aReusedRowStillRendersWhenItsOwnStateChanges() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let counter = Counter()
    let row = StatefulRow(counter: counter)
    let page = StatefulPage(row: row)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    page.tick = 1
    pass(tree)
    #expect(counter.bodies == 1)
    // What the row read when it last ran still reaches it, though its body did not run in the pass above.
    row.taps = 3
    pass(tree)
    #expect(tree.root.renderNode.htmlDescription.contains("taps 3"), Comment(rawValue: tree.root.renderNode.htmlDescription))
    // Then its parent renders: what it remembered from before it rendered on its own is not brought back.
    page.tick = 3
    pass(tree)
    #expect(tree.root.renderNode.htmlDescription.contains("taps 3"), Comment(rawValue: tree.root.renderNode.htmlDescription))
    // Its state and its parent's change in the same batch: it renders.
    page.tick = 2
    row.taps = 4
    pass(tree)
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("even 2") && html.contains("taps 4"), Comment(rawValue: html))
  }

  private struct FramedPage: View {
    @State var width = 100.0
    let counter: Counter
    var body: some View {
      VStack {
        Text("width \(width)")
        Row(title: "a", counter: counter)
      }
      .frame(maxWidth: width)
    }
  }

  @Test
  func aModifierAroundAReusedRowStillAppliesItsNewValue() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let counter = Counter()
    let page = FramedPage(counter: counter)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    page.width = 240
    pass(tree)
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("240"), Comment(rawValue: html))
    #expect(counter.bodies == 1)
  }

  private struct ListPage: View {
    @State var tick = 0
    let titles: [String]
    let counter: Counter
    var body: some View {
      VStack {
        // A branch on the state makes the page render again (a text alone would be updated in place).
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        ForEach(titles, id: \.self) { title in Row(title: title, counter: counter) }
      }
    }
  }

  @Test
  func forEachRowsWhoseInputsDidNotChangeAreNotRenderedAgain() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let counter = Counter()
    let page = ListPage(titles: ["a", "b", "c"], counter: counter)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    #expect(counter.bodies == 3)
    for tick in 1...3 {
      page.tick = tick
      pass(tree)
    }
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("odd 3") && html.contains("row a") && html.contains("row c"), Comment(rawValue: html))
    #expect(counter.bodies == 3, "the rows' bodies ran \(counter.bodies) times")
  }

  private struct RootPage: View {
    let header: String
    let counter: Counter
    var body: some View {
      VStack {
        Text(header)
        Row(title: "a", counter: counter)
      }
    }
  }

  /// A pass from the root (a new root value, an environment change at the root) keeps the owners registered and reuses
  /// what did not change, and the registry does not grow with the passes.
  @Test
  func aPassFromTheRootReusesWhatDidNotChangeAndKeepsTheRegistrySteady() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let counter = Counter()
    let tree = FiberTree(RootPage(header: "h0", counter: counter))
    _ = tree.update(RootPage(header: "h1", counter: counter))
    let settled = tree._registeredOwnerCount
    for index in 2...20 { _ = tree.update(RootPage(header: "h\(index)", counter: counter)) }
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("h20") && html.contains("row a"), Comment(rawValue: html))
    #expect(counter.bodies == 1, "the row's body ran \(counter.bodies) times")
    #expect(tree._registeredOwnerCount == settled)
  }

  private struct Deep: View {
    let level: Int
    let counter: Counter
    var body: some View {
      if level == 0 {
        Row(title: "deep", counter: counter)
      } else {
        VStack { Deep(level: level - 1, counter: counter) }
      }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: Deep, _ rhs: Deep) -> Bool {
      _swiftUIWebSame(lhs.level, rhs.level) && _swiftUIWebSame(lhs.counter, rhs.counter)
    }
  }

  private struct DeepPage: View {
    @State var tick = 0
    let counter: Counter
    var body: some View {
      VStack {
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        Deep(level: 8, counter: counter)
      }
    }
  }

  /// A render deep enough to be handed to the loop that drives the pass (`_RenderStaging`) keeps its content: a view
  /// rendered inside the deferred part is remembered by a copy of what its render turned into
  /// (`_RenderStaging.snapshot`), not by the node that stood in for it, which the deferred render empties.
  @Test
  func aReusedRenderThatWasDeferredKeepsItsContent() {
    _ViewReuse.enabled = true
    let budget = _RenderStaging.budget
    _RenderStaging.budget = 3
    defer { _ViewReuse.enabled = false; _RenderStaging.budget = budget }
    let counter = Counter()
    let page = DeepPage(counter: counter)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    for tick in 1...4 {
      page.tick = tick
      _ = tree.renderNode
      let html = tree.root.renderNode.htmlDescription
      #expect(html.contains("row deep"), "pass \(tick): \(html)")
    }
  }

  private struct ReuseTestButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(Color.blue)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
  }

  private struct StyledLabel: View {
    let title: String
    let counter: Counter
    var body: some View {
      counter.bodies += 1
      return HStack(spacing: 8) { Text(title) }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: StyledLabel, _ rhs: StyledLabel) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.counter, rhs.counter)
    }
  }

  private struct StyledButton: View {
    let title: String
    let counter: Counter
    var body: some View {
      Button {} label: { StyledLabel(title: title, counter: counter) }
        .buttonStyle(ReuseTestButtonStyle())
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: StyledButton, _ rhs: StyledButton) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.counter, rhs.counter)
    }
  }

  private struct Nest<Content: View>: View {
    let level: Int
    @ViewBuilder let content: () -> Content
    var body: some View {
      if level == 0 { content() } else { VStack { Nest(level: level - 1, content: content) } }
    }
  }

  private struct StyledPage: View {
    @State var tick = 0
    let counter: Counter
    var body: some View {
      VStack {
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        Nest(level: 6) {
          StyledButton(title: "create", counter: counter).padding(4)
          StyledButton(title: "search", counter: counter)
        }
      }
    }
  }

  /// The page after `ticks` passes, as HTML, with reuse on or off and a deferral budget (`_RenderStaging`).
  private func styledPage(reuse: Bool, budget: Int, ticks: Int, counter: Counter) -> String {
    _ViewReuse.enabled = reuse
    let previousBudget = _RenderStaging.budget
    _RenderStaging.budget = budget
    defer { _ViewReuse.enabled = false; _RenderStaging.budget = previousBudget }
    let page = StyledPage(counter: counter)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    for tick in 1...max(ticks, 1) where ticks > 0 {
      page.tick = tick
      pass(tree)
    }
    return tree.root.renderNode.htmlDescription
  }

  /// What wraps a reused view (a button style around its label, a modifier at the call site) writes into the node it
  /// gets: what is remembered and handed out again is the node as the view returned it, so a reused render shows what a
  /// fresh one would, deferred (`_RenderStaging`) or not.
  @Test(arguments: [0, 3])
  func aReusedViewInsideAStyleRendersWhatAFreshRenderWould(budget: Int) {
    let reused = Counter()
    let html = styledPage(reuse: true, budget: budget, ticks: 4, counter: reused)
    let fresh = styledPage(reuse: false, budget: budget, ticks: 4, counter: Counter())
    #expect(html == fresh, Comment(rawValue: "reused:\n\(html)\nfresh:\n\(fresh)"))
    #expect(reused.bodies < 10, "the labels' bodies ran \(reused.bodies) times over 5 passes")
  }

  private struct TitledRow: View {
    let counter: Counter
    var body: some View {
      counter.bodies += 1
      return Text("titled").navigationTitle("Row title")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: TitledRow, _ rhs: TitledRow) -> Bool { _swiftUIWebSame(lhs.counter, rhs.counter) }
  }

  private struct TitledStackPage: View {
    @State var tick = 0
    let counter: Counter
    var body: some View {
      NavigationStack {
        VStack {
          // A branch on the state makes the page render again (a text alone would be updated in place).
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
          TitledRow(counter: counter)
        }
      }
    }
  }

  @Test
  func aRowThatGivesItsStackATitleRendersEveryTimeAndKeepsTheTitle() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let counter = Counter()
    let page = TitledStackPage(counter: counter)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    page.tick = 1
    pass(tree)
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("Row title"), Comment(rawValue: html))
    #expect(counter.bodies == 2, "a render that hands its stack a title is not reused")
  }
}

private struct ReuseTestAccentKey: EnvironmentKey { static let defaultValue = "plain" }

extension EnvironmentValues {
  fileprivate var reuseTestAccent: String {
    get { self[ReuseTestAccentKey.self] }
    set { self[ReuseTestAccentKey.self] = newValue }
  }
}

@Suite @MainActor struct ViewInputComparisonTests {
  private struct Facts { let title: String; let items: [Int] }

  @Test func aStructThatIsNotEquatableComparesByItsBytes() {
    let items = [1, 2, 3]
    let facts = Facts(title: "a", items: items)
    #expect(_swiftUIWebSame(facts, facts))
    #expect(_swiftUIWebSame(facts, Facts(title: "a", items: items)), "the same values and the same array storage")
    #expect(!_swiftUIWebSame(facts, Facts(title: "b", items: items)))
    #expect(!_swiftUIWebSame(facts, Facts(title: "a", items: [1, 2, 3])), "a new array is not taken for the same one")
  }
}
