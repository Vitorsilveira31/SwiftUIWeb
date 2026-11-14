import Observation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) @testable import SwiftUIWebFiber

/// Shape of a large app's work card (`StudioWorkCardView`) rebuilt from framework views only: each candidate adds one
/// modifier or subview of the card to a row that compares its inputs. A row that the parent renders again with the same
/// inputs must not render again, so a candidate that does is a culprit.
@Suite(.serialized)
@MainActor
final class CardReuseBisectTests {
  final class BisectLog { var bodies = 0 }

  @Observable final class BisectStore {
    var label = "status"
  }

  /// Non-Hashable, holds closures (as `StudioActions` does).
  struct BisectActions {
    let run: () -> Void
  }

  fileprivate struct BisectActionsKey: EnvironmentKey {
    static var defaultValue: BisectActions { BisectActions(run: {}) }
  }

  /// A row built from `title` and `log` alone: the inputs the probe compares.
  protocol BisectRow: View {
    init(title: String, log: BisectLog)
  }

  private struct Page<Row: BisectRow>: View {
    @State var tick = 0
    let titles: [String]
    let log: BisectLog
    var body: some View {
      VStack {
        // A branch on the state makes the page render again (a text alone would be updated in place).
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        ForEach(titles, id: \.self) { Row(title: $0, log: log) }
      }
    }
  }

  /// How many rows the parent rendered again over two passes with unchanged inputs (0 when every row was remembered).
  /// The probe's root: the page under the card's environment (`store`, `actions`), inside `depth` stacks as the browser's
  /// screens are.
  private func root<P: View>(_ page: P, depth: Int, store: BisectStore, actions: BisectActions) -> AnyView {
    var view = AnyView(page)
    for _ in 0..<depth { view = AnyView(VStack { view }) }
    return AnyView(view.environment(store).environment(\.bisectActions, actions))
  }

  /// `staged` renders with the browser's staging budget (`SWIFTUIWEB_RENDER_STAGE`, 12 in the embedded runtime): a render
  /// deeper than that is deferred to the pass's loop, with the read recorder it had when it was deferred.
  private func rowsRenderedAgain<Row: BisectRow>(_: Row.Type, depth: Int = 0, staged: Bool = false) -> Int {
    _ViewReuse.enabled = true
    let savedBudget = _RenderStaging.budget
    _RenderStaging.budget = staged ? 12 : 0
    defer { _ViewReuse.enabled = false; _RenderStaging.budget = savedBudget }
    let log = BisectLog()
    let page = Page<Row>(titles: ["a", "b", "c"], log: log)
    let store = BisectStore()
    let actions = BisectActions(run: {})
    let tree = FiberTree(root(page, depth: depth, store: store, actions: actions))
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    let initial = log.bodies
    page.tick = 1
    _ = tree.renderNode
    page.tick = 2
    _ = tree.renderNode
    return log.bodies - initial
  }

  private struct LazyGridPage<Row: BisectRow>: View {
    @State var tick = 0
    let titles: [String]
    let log: BisectLog
    var body: some View {
      VStack {
        // A branch on the state makes the page render again (a text alone would be updated in place).
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24, alignment: .top), GridItem(.flexible(), spacing: 24, alignment: .top)], alignment: .leading, spacing: 24) {
          ForEach(titles, id: \.self) { Row(title: $0, log: log) }
        }
      }
    }
  }

  /// How many grid rows the parent rendered again over two passes, each followed by the window request the browser sends
  /// after a commit (`_materializeLazyCollection` over the visible rows).
  private func lazyRowsRenderedAgain<Row: BisectRow>(_: Row.Type, depth: Int = 0, staged: Bool = false) -> Int {
    _ViewReuse.enabled = true
    let savedBudget = _RenderStaging.budget
    _RenderStaging.budget = staged ? 12 : 0
    defer { _ViewReuse.enabled = false; _RenderStaging.budget = savedBudget }
    let log = BisectLog()
    let page = LazyGridPage<Row>(titles: ["a", "b", "c"], log: log)
    let store = BisectStore()
    let actions = BisectActions(run: {})
    let tree = FiberTree(root(page, depth: depth, store: store, actions: actions), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<3), beforeExtent: 0, afterExtent: 0)
    let initial = log.bodies
    for tick in 1...2 {
      page.tick = tick
      _ = tree.renderNode
      let window = tree._lazyCollections()[0].ownerIdentity
      _ = tree._materializeLazyCollection(ownerIdentity: window, indices: Array(0..<3), beforeExtent: 0, afterExtent: 0)
    }
    return log.bodies - initial
  }

  private enum BisectPosterStyle {
    case card(titleSize: Double)
    case thumb
    var width: Double? { if case .thumb = self { 80 } else { nil } }
    var showsTitle: Bool { if case .card = self { true } else { false } }
  }

  /// The card's exact expressions: optional-colour fills chosen by an `if`, an `if case` inside an overlay, an optional frame
  /// from an enum, a localized accessibility label and `Optional.map` in the frame.
  private struct ExactExpressionsRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      let style: BisectPosterStyle = .card(titleSize: 22)
      return Rectangle()
        .fill(Color.black)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .overlay(alignment: .bottomLeading) {
          if case .card(let titleSize) = style {
            Text(title).font(.custom("Newsreader", size: titleSize))
          }
        }
        .frame(width: style.width.map { $0 * 1 }, height: style.width.map { $0 * 4 / 3 })
        .accessibilityHidden(!style.showsTitle)
        .accessibilityLabel(String(localized: "card \(title)"))
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: ExactExpressionsRow, _ rhs: ExactExpressionsRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct ConditionalFillRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      let tone: Int = title.count % 2
      return Group {
        if tone == 0 {
          RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(height: 4).frame(maxWidth: .infinity)
        } else {
          RoundedRectangle(cornerRadius: 2).fill(Color.gray).frame(height: 4).frame(maxWidth: .infinity)
        }
      }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: ConditionalFillRow, _ rhs: ConditionalFillRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  @Test func aRowWithTheCardsExactExpressionsIsRemembered() {
    #expect(rowsRenderedAgain(ExactExpressionsRow.self) == 0)
  }

  @Test func aRowWithAConditionalFillIsRemembered() {
    #expect(rowsRenderedAgain(ConditionalFillRow.self) == 0)
  }

  @Test func lazyRowWithTheCardsExactExpressionsIsRemembered() {
    #expect(lazyRowsRenderedAgain(ExactExpressionsRow.self) == 0)
  }

  /// The environment is written by a holder above the page. `renderNode` evaluates the holder again on every pass, so the
  /// write repeats: a non-Hashable value gets a new stamp each time, and a row that read it in its body renders again.
  private struct Holder<Row: BisectRow>: View {
    let page: Page<Row>
    let store: BisectStore
    let actions: BisectActions
    var body: some View {
      VStack { page }.environment(store).environment(\.bisectActions, actions)
    }
  }

  /// Pins the hazard: a non-Hashable environment value rewritten by an ancestor on every pass makes its readers render again.
  @Test func aRowReadingANonHashableEnvironmentValueWrittenEveryPassRendersAgain() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let log = BisectLog()
    let page = Page<ActionInBodyRow>(titles: ["a", "b", "c"], log: log)
    let tree = FiberTree(Holder(page: page, store: BisectStore(), actions: BisectActions(run: {})))
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    let initial = log.bodies
    page.tick = 1
    _ = tree.renderNode
    page.tick = 2
    _ = tree.renderNode
    #expect(log.bodies - initial == 6, "the rows rendered again \(log.bodies - initial) times, once per row and pass")
  }

  // MARK: Deep and staged, as in the browser: candidates from the plain row to the whole card shape.

  @Test func deepStagedPlainRowIsRemembered() {
    #expect(rowsRenderedAgain(Plain.self, depth: 12, staged: true) == 0)
  }

  @Test func deepStagedEnvironmentObjectRowIsRemembered() {
    #expect(rowsRenderedAgain(EnvironmentObjectRow.self, depth: 12, staged: true) == 0)
  }

  @Test func deepStagedButtonRowIsRemembered() {
    #expect(rowsRenderedAgain(ButtonRow.self, depth: 12, staged: true) == 0)
  }

  @Test func deepStagedGeometryRowIsRemembered() {
    #expect(rowsRenderedAgain(GeometryRow.self, depth: 12, staged: true) == 0)
  }

  @Test func deepStagedPosterRowIsRemembered() {
    #expect(rowsRenderedAgain(PosterRow.self, depth: 12, staged: true) == 0)
  }

  @Test func deepStagedStatusRowIsRemembered() {
    #expect(rowsRenderedAgain(StatusRow.self, depth: 12, staged: true) == 0)
  }

  @Test func deepStagedDotsRowIsRemembered() {
    #expect(rowsRenderedAgain(DotsRow.self, depth: 12, staged: true) == 0)
  }

  @Test func deepStagedWholeCardShapeIsRemembered() {
    #expect(rowsRenderedAgain(CardShapeRow.self, depth: 12, staged: true) == 0)
  }

  @Test func deepStagedLazyWholeCardShapeIsRemembered() {
    #expect(lazyRowsRenderedAgain(CardShapeRow.self, depth: 12, staged: true) == 0)
  }

  @Observable final class BisectQuery {
    var query = ""
  }

  /// The screen as the works list is: its query lives in an `@Observable` model that the screen reads, so typing
  /// re-renders the screen through Observation (native) rather than through `@State`.
  private struct ModelPage<Row: BisectRow>: View {
    let model: BisectQuery
    let titles: [String]
    let log: BisectLog
    var body: some View {
      VStack {
        Text("query \(model.query)")
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24, alignment: .top), GridItem(.flexible(), spacing: 24, alignment: .top)], alignment: .leading, spacing: 24) {
          ForEach(titles, id: \.self) { Row(title: $0, log: log) }
        }
      }
    }
  }

  /// Rows the screen rendered again while its observed query changed twice (native Observation, lazy grid window).
  private func observedQueryRowsRenderedAgain<Row: BisectRow>(_: Row.Type) -> Int {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let log = BisectLog()
    let query = BisectQuery()
    let store = BisectStore()
    let actions = BisectActions(run: {})
    let page = ModelPage<Row>(model: query, titles: ["a", "b", "c"], log: log)
    let tree = FiberTree(VStack { page }.environment(store).environment(\.bisectActions, actions), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<3), beforeExtent: 0, afterExtent: 0)
    let initial = log.bodies
    for letter in ["x", "y"] {
      query.query += letter
      _ = tree.renderNode
      let window = tree._lazyCollections()[0].ownerIdentity
      _ = tree._materializeLazyCollection(ownerIdentity: window, indices: Array(0..<3), beforeExtent: 0, afterExtent: 0)
    }
    return log.bodies - initial
  }

  @Test func observedQueryLazyCardShapeIsRemembered() {
    #expect(observedQueryRowsRenderedAgain(CardShapeRow.self) == 0)
  }

  @Test func observedQueryLazyPlainRowIsRemembered() {
    #expect(observedQueryRowsRenderedAgain(Plain.self) == 0)
  }

  // MARK: Candidates, from the plain row up to the card's whole shape.

  private struct Plain: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      return Text(title)
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: Plain, _ rhs: Plain) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct EnvironmentObjectRow: BisectRow {
    let title: String
    let log: BisectLog
    @Environment(BisectStore.self) private var store
    var body: some View {
      log.bodies += 1
      return Text("\(store.label) \(title)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: EnvironmentObjectRow, _ rhs: EnvironmentObjectRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  /// The card reads its actions only inside the button's action closure, never in its body.
  private struct ActionInClosureRow: BisectRow {
    let title: String
    let log: BisectLog
    @Environment(\.bisectActions) private var actions
    var body: some View {
      log.bodies += 1
      return Button { actions.run() } label: { Text(title) }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: ActionInClosureRow, _ rhs: ActionInClosureRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  /// Control for the body read: the non-Hashable environment value is read during render (see the tests at the end).
  private struct ActionInBodyRow: BisectRow {
    let title: String
    let log: BisectLog
    @Environment(\.bisectActions) private var actions
    var body: some View {
      log.bodies += 1
      let run = actions.run
      return Button { run() } label: { Text(title) }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: ActionInBodyRow, _ rhs: ActionInBodyRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct StateRow: BisectRow {
    let title: String
    let log: BisectLog
    @State private var hovered = false
    var body: some View {
      log.bodies += 1
      return Text(title).foregroundColor(hovered ? .red : .blue)
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: StateRow, _ rhs: StateRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct ButtonRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      return Button { } label: { Text(title) }.buttonStyle(.plain)
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: ButtonRow, _ rhs: ButtonRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct HoverRow: BisectRow {
    let title: String
    let log: BisectLog
    @State private var hovered = false
    var body: some View {
      log.bodies += 1
      return Text(title).onHover { hovered = $0 }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: HoverRow, _ rhs: HoverRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct AccessibilityRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      return Text(title).accessibilityLabel("card \(title)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: AccessibilityRow, _ rhs: AccessibilityRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct EffectsRow: BisectRow {
    let title: String
    let log: BisectLog
    @State private var hovered = false
    var body: some View {
      log.bodies += 1
      return Text(title)
        .shadow(color: hovered ? Color.black.opacity(0.22) : Color.clear, radius: 15, y: 14)
        .offset(y: hovered ? -3 : 0)
        .animation(.easeOut(duration: 0.2), value: hovered)
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: EffectsRow, _ rhs: EffectsRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct LayoutRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      return VStack(alignment: .leading, spacing: 10) { Text(title) }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: LayoutRow, _ rhs: LayoutRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct PosterView: View {
    let title: String
    var body: some View {
      Rectangle()
        .fill(Color.black)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .overlay(alignment: .bottomLeading) {
          ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.4)
            VStack(alignment: .leading, spacing: 6) {
              Text(title).fixedSize(horizontal: false, vertical: true)
              Text("genre").opacity(0.8)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(false)
    }
  }

  private struct PosterRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      return PosterView(title: title)
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: PosterRow, _ rhs: PosterRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct StatusLine: View {
    let text: String
    var body: some View {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "star")
          .font(.system(size: 14))
          .foregroundColor(.red)
          .frame(width: 26, height: 22)
          .background(Color.red.opacity(0.2))
          .clipShape(RoundedRectangle(cornerRadius: 11))
        Text(text)
          .font(.system(size: 13))
          .foregroundColor(.gray)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private struct StatusRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      return StatusLine(text: title)
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: StatusRow, _ rhs: StatusRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct DotsView: View {
    let title: String
    var body: some View {
      HStack(spacing: 4) {
        ForEach(["story", "comic", "audio", "art", "video"], id: \.self) { kind in
          Rectangle().fill(kind == title ? Color.red : Color.gray).frame(width: 4, height: 4)
        }
      }
      .frame(maxWidth: .infinity)
      .accessibilityLabel("dots \(title)")
    }
  }

  private struct DotsRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      return DotsView(title: title)
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: DotsRow, _ rhs: DotsRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  /// The whole card shape: the environment object read, the button, the hover and state, the effects, the layout and the
  /// three subviews.
  private struct CardShapeRow: BisectRow {
    let title: String
    let log: BisectLog
    @Environment(BisectStore.self) private var store
    @State private var hovered = false
    var body: some View {
      log.bodies += 1
      let status = store.label
      return Button {
      } label: {
        VStack(alignment: .leading, spacing: 10) {
          PosterView(title: title)
            .shadow(color: hovered ? Color.black.opacity(0.22) : Color.clear, radius: 15, y: 14)
            .offset(y: hovered ? -3 : 0)
            .animation(.easeOut(duration: 0.2), value: hovered)
          StatusLine(text: status)
          DotsView(title: title)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .onHover { hovered = $0 }
      .accessibilityLabel("card \(title) \(status)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: CardShapeRow, _ rhs: CardShapeRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct GeometryRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      return GeometryReader { proxy in
        Text(title).frame(width: proxy.size.width)
      }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: GeometryRow, _ rhs: GeometryRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  /// The card's focused artwork: a geometry reader around a resizable image asset, clipped.
  private struct FocusedArtRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      return GeometryReader { proxy in
        Image("StudioAtmosphere-mare")
          .resizable()
          .frame(width: proxy.size.width * 1.2, height: proxy.size.height)
          .offset(x: -proxy.size.width * 0.1, y: 0)
      }
      .clipped()
      .accessibilityHidden(true)
      .overlay(alignment: .bottomLeading) { Text(title) }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: FocusedArtRow, _ rhs: FocusedArtRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct NamedPaintRow: BisectRow {
    let title: String
    let log: BisectLog
    var body: some View {
      log.bodies += 1
      return ZStack {
        Rectangle().fill(Color("StudioColor-posterBase"))
        LinearGradient(colors: [Color("StudioColor-freshPoster-1"), Color("StudioColor-freshPoster-2")], startPoint: .topLeading, endPoint: .bottomTrailing)
        Text(title).font(.custom("Newsreader", size: 22)).lineSpacing(3).tracking(-0.2)
      }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: NamedPaintRow, _ rhs: NamedPaintRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  @Test func aRowWithAGeometryReaderIsRemembered() {
    #expect(rowsRenderedAgain(GeometryRow.self) == 0)
  }

  @Test func aRowWithFocusedArtworkIsRemembered() {
    #expect(rowsRenderedAgain(FocusedArtRow.self) == 0)
  }

  @Test func aRowWithNamedPaintAndCustomFontIsRemembered() {
    #expect(rowsRenderedAgain(NamedPaintRow.self) == 0)
  }

  @Test func lazyRowWithAGeometryReaderIsRemembered() {
    #expect(lazyRowsRenderedAgain(GeometryRow.self) == 0)
  }

  @Test func lazyRowWithFocusedArtworkIsRemembered() {
    #expect(lazyRowsRenderedAgain(FocusedArtRow.self) == 0)
  }

  @Test func lazyRowWithNamedPaintAndCustomFontIsRemembered() {
    #expect(lazyRowsRenderedAgain(NamedPaintRow.self) == 0)
  }

  // MARK: One test per candidate. Each expects no row to render again.

  @Test func aPlainRowIsRemembered() {
    #expect(rowsRenderedAgain(Plain.self) == 0)
  }

  @Test func aRowReadingAnEnvironmentObjectIsRemembered() {
    #expect(rowsRenderedAgain(EnvironmentObjectRow.self) == 0)
  }

  @Test func aRowReadingItsActionsOnlyInAClosureIsRemembered() {
    #expect(rowsRenderedAgain(ActionInClosureRow.self) == 0)
  }

  /// Reading the non-Hashable value in the body is what breaks reuse (see the holder test above); the card reads its
  /// actions only inside the button's closure, so it is not affected.
  @Test func aRowReadingItsActionsInItsBodyRendersAgainWithTheRootPass() {
    #expect(rowsRenderedAgain(ActionInBodyRow.self) == 6)
  }

  @Test func aRowWithStateIsRemembered() {
    #expect(rowsRenderedAgain(StateRow.self) == 0)
  }

  @Test func aRowWithAButtonIsRemembered() {
    #expect(rowsRenderedAgain(ButtonRow.self) == 0)
  }

  @Test func aRowWithOnHoverIsRemembered() {
    #expect(rowsRenderedAgain(HoverRow.self) == 0)
  }

  @Test func aRowWithAccessibilityLabelIsRemembered() {
    #expect(rowsRenderedAgain(AccessibilityRow.self) == 0)
  }

  @Test func aRowWithShadowOffsetAndAnimationIsRemembered() {
    #expect(rowsRenderedAgain(EffectsRow.self) == 0)
  }

  @Test func aRowWithFrameAndContentShapeIsRemembered() {
    #expect(rowsRenderedAgain(LayoutRow.self) == 0)
  }

  @Test func aRowWithThePosterSubviewIsRemembered() {
    #expect(rowsRenderedAgain(PosterRow.self) == 0)
  }

  @Test func aRowWithTheStatusSubviewIsRemembered() {
    #expect(rowsRenderedAgain(StatusRow.self) == 0)
  }

  @Test func aRowWithTheDotsSubviewIsRemembered() {
    #expect(rowsRenderedAgain(DotsRow.self) == 0)
  }

  @Test func theWholeCardShapeIsRemembered() {
    #expect(rowsRenderedAgain(CardShapeRow.self) == 0)
  }

  // MARK: The same candidates in a lazy grid, materialized window by window.

  @Test func lazyPlainRowIsRemembered() {
    #expect(lazyRowsRenderedAgain(Plain.self) == 0)
  }

  @Test func lazyRowReadingAnEnvironmentObjectIsRemembered() {
    #expect(lazyRowsRenderedAgain(EnvironmentObjectRow.self) == 0)
  }

  @Test func lazyRowWithStateIsRemembered() {
    #expect(lazyRowsRenderedAgain(StateRow.self) == 0)
  }

  @Test func lazyRowWithAButtonIsRemembered() {
    #expect(lazyRowsRenderedAgain(ButtonRow.self) == 0)
  }

  @Test func lazyRowWithOnHoverIsRemembered() {
    #expect(lazyRowsRenderedAgain(HoverRow.self) == 0)
  }

  @Test func lazyRowWithAccessibilityLabelIsRemembered() {
    #expect(lazyRowsRenderedAgain(AccessibilityRow.self) == 0)
  }

  @Test func lazyRowWithShadowOffsetAndAnimationIsRemembered() {
    #expect(lazyRowsRenderedAgain(EffectsRow.self) == 0)
  }

  @Test func lazyRowWithFrameAndContentShapeIsRemembered() {
    #expect(lazyRowsRenderedAgain(LayoutRow.self) == 0)
  }

  @Test func lazyRowWithThePosterSubviewIsRemembered() {
    #expect(lazyRowsRenderedAgain(PosterRow.self) == 0)
  }

  @Test func lazyRowWithTheStatusSubviewIsRemembered() {
    #expect(lazyRowsRenderedAgain(StatusRow.self) == 0)
  }

  @Test func lazyRowWithTheDotsSubviewIsRemembered() {
    #expect(lazyRowsRenderedAgain(DotsRow.self) == 0)
  }

  @Test func lazyWholeCardShapeIsRemembered() {
    #expect(lazyRowsRenderedAgain(CardShapeRow.self) == 0)
  }
}

extension EnvironmentValues {
  fileprivate var bisectActions: CardReuseBisectTests.BisectActions {
    get { self[CardReuseBisectTests.BisectActionsKey.self] }
    set { self[CardReuseBisectTests.BisectActionsKey.self] = newValue }
  }
}
