import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore

/// A view's `@State` is installed before its body is first evaluated: the body and the view's actions read the same
/// storage, and a later value of the view (its parent rendered again) keeps that storage, its own initial value
/// discarded. Here the state is assigned by the view's initializer, the `onAppear` action reads it at once and the body
/// reads it only in a later render, inside a `GeometryReader` and a condition, as a player shows its picture once the
/// episode is authorized.
@Suite
@MainActor
struct StateInstalledBeforeActionsTests {
  final class Engine {
    let id: Int
    init(id: Int) { self.id = id }
  }

  final class Factory {
    var made = 0
    func make() -> Engine {
      made += 1
      return Engine(id: made)
    }
  }

  final class Log {
    var events: [String] = []
  }

  struct Screen: View {
    @State var engine: Engine
    let log: Log
    let shows: Bool

    init(factory: Factory, log: Log, shows: Bool) {
      self.log = log
      self.shows = shows
      _engine = State(wrappedValue: factory.make())
    }

    var body: some View {
      GeometryReader { _ in
        if shows { Text("drawn\(engine.id)") }
      }
      .onAppear { log.events.append("appear\(engine.id)") }
    }
  }

  final class Model {
    let engine: Engine
    init(engine: Engine) { self.engine = engine }
  }

  /// The same with the model in a `@StateObject`, which is what the Embedded lowering makes of an `@Observable` in `@State`.
  struct ModelScreen: View {
    @StateObject var model: Model
    let log: Log
    let shows: Bool

    init(factory: Factory, log: Log, shows: Bool) {
      self.log = log
      self.shows = shows
      _model = StateObject(wrappedValue: Model(engine: factory.make()))
    }

    var body: some View {
      GeometryReader { _ in
        if shows { Text("drawn\(model.engine.id)") }
      }
      .onAppear { log.events.append("appear\(model.engine.id)") }
    }
  }

  /// The parent of the screen, rendered again with another input: each render makes a new value of the screen.
  struct Route<Content: View>: View {
    let pass: Int
    let content: () -> Content
    var body: some View {
      VStack {
        Text("pass\(pass)")
        content()
      }
    }
  }

  /// Renders `make()` three times with render staging at `budget` (the browser defers part of a deep render: Embedded
  /// uses 12) and returns what the screen's `onAppear` read and what its reader drew.
  private func run<V: View>(budget: Int, _ make: @escaping (Factory, Log, Bool) -> V) -> (made: Int, events: [String], html: String) {
    let saved = _RenderStaging.budget
    _RenderStaging.budget = budget
    defer { _RenderStaging.budget = saved }
    let factory = Factory()
    let log = Log()
    func route(_ pass: Int) -> some View { Route(pass: pass) { make(factory, log, pass > 0) } }
    let tree = FiberTree(route(0))
    _ = tree.update(route(1))
    _ = tree.update(route(2))
    return (factory.made, log.events, tree.renderNode.htmlDescription)
  }

  @Test(arguments: [0, 1, 2, 5, 12])
  func actionsAndAGeometryReaderReadTheStateTheViewWasInstalledWith(budget: Int) {
    let result = run(budget: budget) { Screen(factory: $0, log: $1, shows: $2) }
    #expect(result.made == 3, "each render of the parent makes a value of the screen")
    #expect(result.events == ["appear1"])
    #expect(result.html.contains("drawn1"))
  }

  @Test(arguments: [0, 1, 2, 5, 12])
  func actionsAndAGeometryReaderReadTheStateObjectTheViewWasInstalledWith(budget: Int) {
    let result = run(budget: budget) { ModelScreen(factory: $0, log: $1, shows: $2) }
    #expect(result.events == ["appear1"])
    #expect(result.html.contains("drawn1"))
  }
}
