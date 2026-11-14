import Observation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) @testable import SwiftUIWebFiber

/// A view that reads an environment object by its type (`@Environment(Model.self)`) is remembered and reused like any other
/// view whose inputs did not change. It renders again when the object it read was replaced, when a property of that object
/// that it read changed, or when its own state changed, and not otherwise.
@Suite(.serialized)
@MainActor
struct EnvironmentObjectReuseTests {
  @Observable final class Model {
    var label: String
    var unrelated = 0
    init(_ label: String) { self.label = label }
  }

  final class Log { var bodies = 0 }

  private struct Row: View {
    let title: String
    let log: Log
    @Environment(Model.self) private var model
    var body: some View {
      log.bodies += 1
      return Text("\(model.label) \(title)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: Row, _ rhs: Row) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct Page: View {
    @State var tick = 0
    let model: Model
    let titles: [String]
    let log: Log
    var body: some View {
      VStack {
        // A branch on the state makes the page render again (a text alone would be updated in place).
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        ForEach(titles, id: \.self) { Row(title: $0, log: log) }
      }
      .environment(model)
    }
  }

  private let titles = ["a", "b", "c"]

  private func pass(_ tree: FiberTree) { _ = tree.renderNode }

  private func setUpReuse() -> () -> Void {
    _ViewReuse.enabled = true
    return { _ViewReuse.enabled = false }
  }

  /// The same object, nothing it read changed: the rows are not rendered again with their parent.
  @Test
  func aRowReadingTheSameObjectIsNotRenderedAgainWithItsParent() {
    let restore = setUpReuse()
    defer { restore() }
    let log = Log()
    let page = Page(model: Model("first"), titles: titles, log: log)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    #expect(log.bodies == 3)
    page.tick = 1
    pass(tree)
    #expect(tree.root.renderNode.htmlDescription.contains("odd 1"))
    #expect(log.bodies == 3, "the rows' bodies ran \(log.bodies) times")
  }

  /// The parent passes another object: every row that read it renders again, and shows the new one.
  @Test
  func aRowRendersAgainWhenAnotherObjectTakesThePlaceOfTheOneItRead() {
    let restore = setUpReuse()
    defer { restore() }
    let log = Log()
    let tree = FiberTree(Page(model: Model("first"), titles: titles, log: log))
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    #expect(log.bodies == 3)
    _ = tree.update(Page(model: Model("second"), titles: titles, log: log))
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("second a") && html.contains("second c"), Comment(rawValue: html))
    #expect(log.bodies == 6, "the rows' bodies ran \(log.bodies) times")
  }

  /// A property the row read changes: the row renders again in a normal pass, and shows the new value.
  @Test
  func aRowRendersAgainWhenAPropertyOfTheObjectItReadChanges() {
    let restore = setUpReuse()
    defer { restore() }
    let log = Log()
    let model = Model("first")
    let tree = FiberTree(VStack { Page(model: model, titles: titles, log: log) })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    #expect(log.bodies == 3)
    model.label = "second"
    pass(tree)
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("second a") && html.contains("second c"), Comment(rawValue: html))
    #expect(log.bodies == 6, "the rows' bodies ran \(log.bodies) times")
  }

  /// A property no row read changes: no row renders again.
  @Test
  func aRowIsNotRenderedAgainForAPropertyItDidNotRead() {
    let restore = setUpReuse()
    defer { restore() }
    let log = Log()
    let model = Model("first")
    let tree = FiberTree(VStack { Page(model: model, titles: titles, log: log) })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    model.unrelated = 5
    pass(tree)
    #expect(log.bodies == 3, "the rows' bodies ran \(log.bodies) times")
  }

  private struct TappingRow: View {
    let title: String
    let log: Log
    @Environment(Model.self) private var model
    @State private var taps = 0
    var body: some View {
      log.bodies += 1
      return VStack {
        Button("tap") { taps += 1 }
        Text("\(model.label) \(title) taps \(taps)")
      }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: TappingRow, _ rhs: TappingRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  /// The row's own state changes: it renders again with the state, and keeps reading the object.
  @Test
  func aRowRendersAgainWhenItsOwnStateChanges() {
    let restore = setUpReuse()
    defer { restore() }
    let log = Log()
    let tree = FiberTree(VStack { TappingRow(title: "a", log: log).environment(Model("first")) })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    #expect(log.bodies == 1)
    tree.dispatch(event: "click")
    pass(tree)
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("first a taps 1"), Comment(rawValue: html))
    #expect(log.bodies == 2, "the row's body ran \(log.bodies) times")
  }

  /// The stamp an environment object is read by names that object, and keeps it alive while a memo holds the stamp, so
  /// another object is never taken for the one a render read.
  @Test
  func anEnvironmentObjectReadIsRecordedByTheStampOfTheObjectItReturned() {
    var environment = EnvironmentValues()
    let stored = _storedTypeID(Model.self)
    let stamp = _objectStampID(Model.self)
    let recorder = _EnvironmentReadRecorder()
    let enclosing = EnvironmentValues._readRecorder
    EnvironmentValues._readRecorder = recorder
    defer { EnvironmentValues._readRecorder = enclosing }

    let first = Model("first")
    environment._setEnvironmentObject(first)
    let read = environment._environmentObjectByIdentifier(stored, stamp: stamp, as: Model.self)
    #expect(read === first)
    #expect(!recorder.untracked, "an object read with its stamp is recorded, not left untracked")
    #expect(recorder.reads.count == 1)
    #expect(recorder.reads.first?.stamp == environment._stamp(for: stamp))

    var replaced = environment
    replaced._setEnvironmentObject(Model("second"))
    #expect(recorder.reads.first?.stamp != replaced._stamp(for: stamp), "another object has another stamp")
    #expect(recorder.reads.first?.stamp == environment._stamp(for: stamp), "the original environment is unchanged")
  }

  @Test
  func aStampKeepsItsObjectAliveWhileItIsRecorded() {
    weak var released: Model?
    let recorder = _EnvironmentReadRecorder()
    do {
      var environment = EnvironmentValues()
      let model = Model("old")
      released = model
      environment._setEnvironmentObject(model)
      recorder.reads.append((key: _objectStampID(Model.self), stamp: environment._stamp(for: _objectStampID(Model.self))))
    }
    #expect(released != nil, "the recorded stamp let its object go")
    recorder.reads.removeAll()
    #expect(released == nil, "the object outlived every stamp of it")
  }

  /// What the Embedded browser's observation bridge does for an `@Observable` property (`_recordPublishedObservation` in
  /// the render that read it, `_publishedObservationDidChange` on a write). Native builds do not compile the bridge's
  /// `recordObservation`/`notifyObservers` side, so this drives the same two entry points directly.
  final class BridgeModel {
    var label: String
    let source = _StateSourceID(rawValue: 9_000_000_001)
    var store: StateStore?
    init(_ label: String) { self.label = label }
  }

  private struct BridgeRow: View {
    let title: String
    let log: Log
    let model: BridgeModel
    @Environment(BridgeModel.self) private var env
    var body: some View {
      log.bodies += 1
      if let store = StateRuntime.scope?.store {
        model.store = store
        store._recordPublishedObservation(model.source)
      }
      return Text("\(env.label) \(model.label) \(title)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: BridgeRow, _ rhs: BridgeRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log) && _swiftUIWebSame(lhs.model, rhs.model)
    }
  }

  private struct BridgePage: View {
    @State var tick = 0
    let model: BridgeModel
    let log: Log
    var body: some View {
      VStack {
        if tick % 2 == 0 { Text("even \(tick)") } else { Text("odd \(tick)") }
        ForEach(["a", "b", "c"], id: \.self) { BridgeRow(title: $0, log: log, model: model) }
      }
      .environment(model)
    }
  }

  final class PublishedModel: ObservableObject {
    @Published var label: String
    init(_ label: String) { self.label = label }
  }

  private struct PublishedRow: View {
    let title: String
    let log: Log
    @Environment(PublishedModel.self) private var model
    var body: some View {
      log.bodies += 1
      return Text("\(model.label) \(title)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: PublishedRow, _ rhs: PublishedRow) -> Bool {
      _swiftUIWebSame(lhs.title, rhs.title) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct PublishedList: View {
    let model: PublishedModel
    let log: Log
    var body: some View {
      VStack { ForEach(["a", "b", "c"], id: \.self) { PublishedRow(title: $0, log: log) } }
        .environment(model)
    }
  }

  /// An `ObservableObject` the row read: its write reaches the row's owner when the refresh it schedules runs (one turn
  /// later, not inside the write), so a pass after that turn renders the row again.
  @Test
  func aRowRendersAgainAfterAnObservableObjectItReadChangesAndItsRefresh() async {
    let restore = setUpReuse()
    defer { restore() }
    let log = Log()
    let model = PublishedModel("first")
    let tree = FiberTree(PublishedList(model: model, log: log))
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    #expect(log.bodies == 3)
    model.label = "second"
    await Task.yield()
    await Task.yield()
    pass(tree)
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("second a") && html.contains("second c"), Comment(rawValue: html))
    #expect(log.bodies == 6, "the rows' bodies ran \(log.bodies) times")
  }

  /// The Embedded bridge's observation of a property the row read marks the row's owner: it renders again, and the rows
  /// that did not read it do not.
  @Test
  func aRowRendersAgainWhenAPropertyTheBridgeObservedChanges() {
    let restore = setUpReuse()
    defer { restore() }
    let log = Log()
    let model = BridgeModel("first")
    let page = BridgePage(model: model, log: log)
    let tree = FiberTree(VStack { page })
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    #expect(log.bodies == 3)
    page.tick = 1
    pass(tree)
    #expect(log.bodies == 3, "an unrelated change rendered the rows again: \(log.bodies)")
    model.label = "second"
    model.store?._publishedObservationDidChange(model.source)
    pass(tree)
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("second second a") && html.contains("second second c"), Comment(rawValue: html))
    #expect(log.bodies == 6, "the rows' bodies ran \(log.bodies) times")
  }
}
