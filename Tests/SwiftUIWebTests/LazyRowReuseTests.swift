import Observation
import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A row of a lazy collection whose inputs, environment and state did not change is not rendered again when the host
/// materializes the window again after its parent rendered (the page's lazy window request after each commit).
@Suite @MainActor struct LazyRowReuseTests {
  final class Log { var bodies = 0 }

  private struct Row: View {
    let item: String
    let log: Log
    var body: some View {
      log.bodies += 1
      return Text("row \(item)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: Row, _ rhs: Row) -> Bool {
      _swiftUIWebSame(lhs.item, rhs.item) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  /// Typing changes `query` and nothing the rows read.
  private struct Searching: View {
    @State private var query = ""
    let items: [String]
    let log: Log
    var body: some View {
      VStack {
        Button("type") { query += "x" }
        Text("query \(query)")
        LazyVStack { ForEach(items, id: \.self) { Row(item: $0, log: log) } }
      }
    }
  }

  /// Editing the data of one row changes the inputs of that row only.
  private struct Editing: View {
    @State private var items = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"]
    let log: Log
    var body: some View {
      VStack {
        Button("edit") { items[2] = "Gamma edited" }
        LazyVStack { ForEach(items, id: \.self) { Row(item: $0, log: log) } }
      }
    }
  }

  private let names = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"]

  @Test
  func rowsOfALazyWindowWhoseInputsDidNotChangeAreNotRenderedAgain() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let log = Log()
    let tree = FiberTree(Searching(items: names, log: log), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    #expect(log.bodies == 5)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("query x"), Comment(rawValue: html))
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    #expect(tree.renderNode.htmlDescription.contains("row Epsilon"))
    #expect(log.bodies == 5, "the rows' bodies ran \(log.bodies) times")
  }

  @Test
  func aRowWhoseDataChangedIsRenderedAgainAndOnlyThatRow() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let log = Log()
    let tree = FiberTree(Editing(log: log), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    #expect(log.bodies == 5)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("row Gamma edited"), Comment(rawValue: html))
    #expect(log.bodies == 6, "the rows' bodies ran \(log.bodies) times")
  }

  final class Store {
    let label: String
    init(_ label: String) { self.label = label }
  }

  @Observable final class LabelModel {
    var label: String
    init(_ label: String) { self.label = label }
  }

  /// A row that reads an environment object by its type (`@Environment(Store.self)`), as a large app's work cards do.
  private struct StoreRow: View {
    let item: String
    let log: Log
    @Environment(Store.self) private var store
    var body: some View {
      log.bodies += 1
      return Text("\(store.label) \(item)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: StoreRow, _ rhs: StoreRow) -> Bool {
      _swiftUIWebSame(lhs.item, rhs.item) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct StoreSearching: View {
    @State private var query = ""
    let items: [String]
    let log: Log
    let store: Store
    var body: some View {
      VStack {
        Button("type") { query += "x" }
        Text("query \(query)")
        LazyVStack { ForEach(items, id: \.self) { StoreRow(item: $0, log: log) } }
      }
      .environment(store)
    }
  }

  @Test
  func aRowThatReadsAnEnvironmentObjectByTypeIsNotRenderedAgainWhenNothingChanged() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let log = Log()
    let tree = FiberTree(StoreSearching(items: names, log: log, store: Store("store")), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    #expect(log.bodies == 5)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    #expect(tree.renderNode.htmlDescription.contains("store Epsilon"))
    #expect(log.bodies == 5, "the rows' bodies ran \(log.bodies) times")
  }

  /// The parent passes another object: the rows that read the old one render again and show the new one.
  @Test
  func aLazyRowRendersAgainWhenAnotherObjectTakesThePlaceOfTheOneItRead() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let log = Log()
    let tree = FiberTree(StoreSearching(items: names, log: log, store: Store("store")), deferLazyCollections: true)
    var owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    #expect(log.bodies == 5)
    _ = tree.update(StoreSearching(items: names, log: log, store: Store("other")))
    owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("other Epsilon"), Comment(rawValue: html))
    #expect(log.bodies == 10, "the rows' bodies ran \(log.bodies) times")
  }

  private struct LabelRow: View {
    let item: String
    let log: Log
    @Environment(LabelModel.self) private var model
    var body: some View {
      log.bodies += 1
      return Text("\(model.label) \(item)")
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: LabelRow, _ rhs: LabelRow) -> Bool {
      _swiftUIWebSame(lhs.item, rhs.item) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct LabelList: View {
    let items: [String]
    let log: Log
    let model: LabelModel
    var body: some View {
      VStack {
        LazyVStack { ForEach(items, id: \.self) { LabelRow(item: $0, log: log) } }
      }
      .environment(model)
    }
  }

  /// A property of the observed object that the row read changes: the row renders again with the new value, and the
  /// window shows it on the next request.
  @Test
  func aLazyRowRendersAgainWhenAPropertyOfItsObjectChanges() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let log = Log()
    let model = LabelModel("first")
    let tree = FiberTree(LabelList(items: names, log: log, model: model), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    #expect(log.bodies == 5)
    model.label = "second"
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    #expect(log.bodies == 10, "the rows' bodies ran \(log.bodies) times")
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("second Epsilon"), Comment(rawValue: html))
  }

  private struct TappingRow: View {
    let item: String
    let log: Log
    @Environment(Store.self) private var store
    @State private var taps = 0
    var body: some View {
      log.bodies += 1
      return VStack {
        Button("tap") { taps += 1 }
        Text("\(store.label) \(item) taps \(taps)")
      }
    }
    static var _comparesInputs: Bool { true }
    static func _sameInputs(_ lhs: TappingRow, _ rhs: TappingRow) -> Bool {
      _swiftUIWebSame(lhs.item, rhs.item) && _swiftUIWebSame(lhs.log, rhs.log)
    }
  }

  private struct TappingList: View {
    let items: [String]
    let log: Log
    let store: Store
    var body: some View {
      VStack {
        LazyVStack { ForEach(items, id: \.self) { TappingRow(item: $0, log: log) } }
      }
      .environment(store)
    }
  }

  /// The row's own state changes: it renders again, and keeps reading the object it read before.
  @Test
  func aLazyRowRendersAgainWhenItsOwnStateChanges() {
    _ViewReuse.enabled = true
    defer { _ViewReuse.enabled = false }
    let log = Log()
    let tree = FiberTree(TappingList(items: names, log: log, store: Store("store")), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: [0], beforeExtent: 0, afterExtent: 0)
    #expect(log.bodies == 1)
    tree.dispatch(event: "click")
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: [0], beforeExtent: 0, afterExtent: 0)
    #expect(log.bodies == 2, "the row's body ran \(log.bodies) times")
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("store Alpha taps 1"), Comment(rawValue: html))
  }
}
