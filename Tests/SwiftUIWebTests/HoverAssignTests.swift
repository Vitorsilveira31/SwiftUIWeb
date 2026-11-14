import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

@Suite
@MainActor
final class HoverAssignTests {
  private struct StyleOnlyCard: View {
    @State private var hovered = false
    var body: some View {
      Text("Card")
        .padding(8)
        .background(hovered ? Color.red : Color.blue)
        .opacity(hovered ? 1 : 0.8)
        .onHover(_assigning: _hovered)
    }
  }

  private struct TextChangingCard: View {
    @State private var hovered = false
    var body: some View {
      Text(hovered ? "Hovered" : "Card").onHover(_assigning: _hovered)
    }
  }

  private struct Host<Content: View>: View {
    let content: Content
    var body: some View { VStack { content } }
  }

  /// One publication at `epoch` with the host having acknowledged `acked`: the hover rule changes it carries.
  private func publish(_ tree: FiberTree, epoch: UInt64, acked: UInt64) -> String? {
    let changes = tree._hoverRuleChanges(acked: acked)
    tree._hoverRulesPublished(epoch: epoch)
    return changes
  }

  private func resolveEveryHover(in tree: FiberTree) -> Int {
    var resolved = 0
    func visit(_ fiber: Fiber) {
      if fiber.renderNode._hoverProbe != nil, tree._resolveHover(for: fiber) { resolved += 1 }
      for child in fiber.children { visit(child) }
    }
    visit(tree.root)
    return resolved
  }

  private func trigger(in fiber: Fiber) -> Fiber? {
    if fiber.renderNode._hoverProbe != nil { return fiber }
    for child in fiber.children { if let found = trigger(in: child) { return found } }
    return nil
  }

  @Test
  func aStyleOnlyHoverBecomesCSSAndLeavesTheStateUntouched() throws {
    let tree = FiberTree(Host(content: StyleOnlyCard()))
    let fiber = try #require(trigger(in: tree.root))
    #expect(tree._resolveHover(for: fiber))
    let rules = try #require(publish(tree, epoch: 1, acked: 0))
    #expect(rules.hasPrefix("+"), Comment(rawValue: rules))
    #expect(rules.contains(":has("), Comment(rawValue: rules))
    #expect(rules.contains("opacity:1 !important"), Comment(rawValue: rules))
    #expect(tree.renderNode.htmlDescription.contains("Card"), "the real state must stay un-hovered")
    #expect(publish(tree, epoch: 2, acked: 1) == nil, "rules the host acknowledged are not sent again until they change")
  }

  @Test
  func aNewHoverLearnedLaterKeepsItsEventsUntilThenAndIsMarkedChanged() throws {
    let tree = FiberTree(Host(content: StyleOnlyCard()))
    let fiber = try #require(trigger(in: tree.root))
    #expect(!tree._resolveHover(for: fiber, deferringNew: true), "a deferred hover keeps its pointer events")
    #expect(tree._hasDeferredHover)
    #expect(publish(tree, epoch: 1, acked: 0) == nil, "nothing is learned before the deferred pass")
    let epoch = tree._advanceEpoch() + 1
    tree._learnDeferredHover()
    #expect(!tree._hasDeferredHover)
    #expect(fiber.version == epoch && tree.root.version == epoch, "the next publication visits the fiber and its ancestors")
    #expect(tree._resolveHover(for: fiber, deferringNew: true), "once learned, the rules are used")
    let rules = try #require(publish(tree, epoch: 2, acked: 1))
    #expect(rules.hasPrefix("+"), Comment(rawValue: rules))
  }

  @Test
  func aHoverRuleIsSentAgainUntilTheHostAcknowledgesIt() throws {
    let tree = FiberTree(Host(content: StyleOnlyCard()))
    let fiber = try #require(trigger(in: tree.root))
    #expect(tree._resolveHover(for: fiber))
    let rules = try #require(publish(tree, epoch: 1, acked: 0))
    #expect(publish(tree, epoch: 2, acked: 0) == rules, "a publication the host never committed must not lose the rule")
    #expect(publish(tree, epoch: 3, acked: 2) == nil)
  }

  private struct CardList: View {
    let count: Int
    var body: some View {
      VStack { ForEach(0..<count, id: \.self) { _ in StyleOnlyCard() } }
    }
  }

  @Test
  func aListThatLosesACardSendsOnlyThatCardsRemoval() throws {
    let tree = FiberTree(Host(content: CardList(count: 3)))
    #expect(resolveEveryHover(in: tree) == 3)
    let rules = try #require(publish(tree, epoch: 1, acked: 0))
    #expect(rules.split(separator: "\n").count == 3, Comment(rawValue: rules))

    _ = tree.update(Host(content: CardList(count: 2)))
    _ = resolveEveryHover(in: tree)
    let changes = try #require(publish(tree, epoch: 2, acked: 1))
    #expect(changes.split(separator: "\n").count == 1 && changes.hasPrefix("-"), Comment(rawValue: changes))
  }

  @Test
  func aRemovedHoverTriggerWithdrawsItsPublishedRule() throws {
    let tree = FiberTree(Host(content: StyleOnlyCard()))
    let fiber = try #require(trigger(in: tree.root))
    #expect(tree._resolveHover(for: fiber))
    let rules = try #require(publish(tree, epoch: 1, acked: 0))
    #expect(!rules.isEmpty)

    _ = tree.update(Host(content: EmptyView()))
    #expect(trigger(in: tree.root) == nil)
    let removal = try #require(publish(tree, epoch: 2, acked: 1))
    #expect(removal.hasPrefix("-") && !removal.contains("\t"), "the stale rule must be removed: \(removal)")
    #expect(publish(tree, epoch: 3, acked: 2) == nil)
  }

  @Test
  func aHoverThatChangesTextKeepsTheSwiftEvents() throws {
    let tree = FiberTree(Host(content: TextChangingCard()))
    let fiber = try #require(trigger(in: tree.root))
    #expect(!tree._resolveHover(for: fiber))
    #expect(fiber.renderNode.events["mouseenter"] != nil)
  }

  private struct HoverBackground: ViewModifier {
    let base: Color
    let hover: Color
    @State private var hovered = false
    func body(content: Content) -> some View {
      content.background(hovered ? hover : base).onHover(_assigning: _hovered)
    }
  }

  @Test
  func aViewModifierWithItsOwnHoverStateResolves() throws {
    let tree = FiberTree(Host(content: Text("Chip").modifier(HoverBackground(base: .blue, hover: .red))))
    let fiber = try #require(trigger(in: tree.root))
    #expect(tree._resolveHover(for: fiber))
  }

  private struct ClearStroke: View {
    @State private var hovered = false
    var body: some View {
      Text("Chip")
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(hovered ? Color.red : Color.clear, lineWidth: 1) }
        .onHover(_assigning: _hovered)
    }
  }

  @Test
  func anOutlineThatAppearsOnHoverResolves() throws {
    let tree = FiberTree(Host(content: ClearStroke()))
    let fiber = try #require(trigger(in: tree.root))
    #expect(tree._resolveHover(for: fiber))
  }

  private struct DashedStroke: View {
    @State private var hovered = false
    var body: some View {
      Text("Chip")
        .overlay { Capsule().strokeBorder(hovered ? Color.red : Color.gray, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
        .onHover(_assigning: _hovered)
    }
  }

  @Test
  func aDashedOutlineResolves() throws {
    let tree = FiberTree(Host(content: DashedStroke()))
    let fiber = try #require(trigger(in: tree.root))
    #expect(tree._resolveHover(for: fiber))
  }

  private struct LiftParent: View {
    @State private var hovered = false
    var body: some View {
      VStack { LiftChild() }
        .environment(\.studioTestLifting, hovered)
        .onHover(_assigning: _hovered)
    }
  }
  private struct LiftChild: View {
    @Environment(\.studioTestLifting) private var lifted
    var body: some View {
      Text("Card")
        .shadow(color: lifted ? Color.black.opacity(0.22) : Color.clear, radius: 15, y: 14)
        .offset(y: lifted ? -3 : 0)
        .animation(.easeOut(duration: 0.2), value: lifted)
    }
  }

  @Test
  func aLiftThroughTheEnvironmentResolves() throws {
    let tree = FiberTree(Host(content: LiftParent()))
    let fiber = try #require(trigger(in: tree.root))
    #expect(tree._resolveHover(for: fiber))
  }
  private struct ButtonCard: View {
    @State private var hovered = false
    var body: some View {
      Button {} label: {
        VStack {
          Text("Poster")
            .shadow(color: hovered ? Color.black.opacity(0.22) : Color.clear, radius: 15, y: 14)
            .offset(y: hovered ? -3 : 0)
            .animation(.easeOut(duration: 0.2), value: hovered)
          Text("Status")
        }
      }
      .buttonStyle(.plain)
      .onHover(_assigning: _hovered)
    }
  }

  @Test
  func aButtonCardThatLiftsItsPosterProducesATransformRule() throws {
    let tree = FiberTree(Host(content: ButtonCard()))
    let fiber = try #require(trigger(in: tree.root))
    #expect(tree._resolveHover(for: fiber))
    let rules = try #require(publish(tree, epoch: 1, acked: 0))
    #expect(rules.contains("translate(0px, -3px)"), Comment(rawValue: rules))
  }

  private struct LazyGridHost: View {
    var body: some View {
      ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
          ForEach(0..<4, id: \.self) { _ in ButtonCard() }
        }
      }
    }
  }

  @Test
  func cardsInsideALazyGridProduceTransformRulesToo() throws {
    let tree = FiberTree(LazyGridHost(), deferLazyCollections: true, rootLayoutProposal: nil, startLifecycle: false)
    for info in tree._lazyCollections() {
      _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: Array(0..<info.descriptor.count), beforeExtent: 0, afterExtent: 0)
    }
    _ = tree.renderNode
    var resolved = 0
    func visit(_ fiber: Fiber) {
      if fiber.renderNode._hoverProbe != nil, tree._resolveHover(for: fiber) { resolved += 1 }
      for child in fiber.children { visit(child) }
    }
    visit(tree.root)
    #expect(resolved == 4)
    let rules = try #require(publish(tree, epoch: 1, acked: 0))
    #expect(rules.components(separatedBy: "translate(0px, -3px)").count - 1 == 4, Comment(rawValue: rules))
  }

  private struct LoweredCard: View {
    @Environment(\.isEnabled) private var isEnabled
    @State(memberID: 424242) private var hovered = false
    var body: some View {
      Button {} label: {
        VStack {
          Text("Poster")
            .shadow(color: hovered ? Color.black.opacity(0.22) : Color.clear, radius: 15, y: 14)
            .offset(y: hovered ? -3 : 0)
          Text(isEnabled ? "on" : "off")
        }
      }
      .buttonStyle(.plain)
      .onHover(_assigning: _hovered)
    }
  }

  @Test
  func aLoweredMemberIDStateWithEnvironmentResolves() throws {
    let tree = FiberTree(LazyGridLowered(), deferLazyCollections: true, rootLayoutProposal: nil, startLifecycle: false)
    for info in tree._lazyCollections() {
      _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: Array(0..<info.descriptor.count), beforeExtent: 0, afterExtent: 0)
    }
    _ = tree.renderNode
    var resolved = 0, total = 0
    func visit(_ fiber: Fiber) {
      if fiber.renderNode._hoverProbe != nil { total += 1; if tree._resolveHover(for: fiber) { resolved += 1 } }
      for child in fiber.children { visit(child) }
    }
    visit(tree.root)
    #expect(total == 3)
    #expect(resolved == 3)
  }

  @Observable final class FakeStore { var releases = [1, 2] }
  private struct Poster: View {
    let title: String
    var body: some View { Text(title).padding(4) }
  }
  private struct FaithfulCard: View {
    let title: String
    @Environment(FakeStore.self) private var store
    @State(memberID: 515151) private var hovered = false
    var body: some View {
      let status = "\(store.releases.count) releases"
      Button {} label: {
        VStack(alignment: .leading, spacing: 10) {
          Poster(title: title)
            .shadow(color: hovered ? Color.black.opacity(0.22) : Color.clear, radius: 15, y: 14)
            .offset(y: hovered ? -3 : 0)
            .animation(.easeOut(duration: 0.2), value: hovered)
          Text(status)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .onHover(_assigning: _hovered)
      .accessibilityLabel(title)
    }
  }
  private struct FaithfulShelf: View {
    let store = FakeStore()
    var body: some View {
      ScrollView { HStack { ForEach(["a", "b", "c"], id: \.self) { FaithfulCard(title: $0) } } }
        .environment(store)
    }
  }

  @Test
  func aFaithfulWorkCardResolves() throws {
    let tree = FiberTree(FaithfulShelf())
    _ = tree.renderNode
    var resolved = 0, total = 0
    func visit(_ fiber: Fiber) {
      if fiber.renderNode._hoverProbe != nil { total += 1; if tree._resolveHover(for: fiber) { resolved += 1 } }
      for child in fiber.children { visit(child) }
    }
    visit(tree.root)
    #expect(total == 3)
    #expect(resolved == 3)
  }

  private struct LazyGridLowered: View {
    var body: some View {
      ScrollView { LazyVGrid(columns: [GridItem(.flexible())]) { ForEach(0..<3, id: \.self) { _ in LoweredCard() } } }
    }
  }
}

private enum HoverTestLiftKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
  var studioTestLifting: Bool {
    get { self[HoverTestLiftKey.self] }
    set { self[HoverTestLiftKey.self] = newValue }
  }
}

@Suite
@MainActor
struct HoverDifferenceTests {
  @Test
  func rendererMetadataAddedAfterRenderingIsNotADifference() {
    let normal = _RenderNode.element("button")
    normal.classes = ["push-button", "lazy-cell"]
    normal.attributes = ["data-lazy-index": "3", "data-lazy-owner": "x", "data-background-style": "blue"]
    normal.styles = ["opacity": "0.8"]
    let hovered = _RenderNode.element("button")
    hovered.classes = ["push-button"]
    hovered.attributes = ["data-background-style": "red"]
    hovered.styles = [:]

    let differences = _hoverDifferences(normal: normal, hovered: hovered)
    #expect(differences?.count == 1)
    #expect(differences?.first?.declarations == ["opacity": "unset"])
  }

  @Test
  func textOrStructureChangesAreNotStyleOnly() {
    let normal = _RenderNode.element("div")
    normal.children = [_RenderNode.text("a")]
    let changed = _RenderNode.element("div")
    changed.children = [_RenderNode.text("b")]
    #expect(_hoverDifferences(normal: normal, hovered: changed) == nil)
    let extra = _RenderNode.element("div")
    extra.children = [_RenderNode.text("a"), _RenderNode.text("a")]
    #expect(_hoverDifferences(normal: normal, hovered: extra) == nil)
  }
}
