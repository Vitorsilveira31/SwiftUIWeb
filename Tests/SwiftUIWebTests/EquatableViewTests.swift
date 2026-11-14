import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@MainActor private final class _BodyCounter { var count = 0 }

private struct _CountedRow: View, Equatable {
  let id: Int
  let value: Int
  let counter: _BodyCounter
  @Environment(\.font) private var font
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.value == rhs.value }
  var body: some View {
    counter.count += 1
    return HStack(spacing: 8) {
      Text("Row \(id)")
      Spacer()
      Text("value \(value)")
      // Reads the font, so a font change is a change of this row's environment.
      if font == .title { Text("title") }
    }
  }
}

private struct _CountedList: View {
  let values: [Int]
  let counter: _BodyCounter
  var font: Font = .body
  var header = ""
  var body: some View {
    VStack(spacing: 0) {
      // Something outside the rows that can change, so an update is not reused whole as an unchanged template.
      Text(header)
      ForEach(Array(values.enumerated()), id: \.offset) { item in
        _CountedRow(id: item.offset, value: item.element, counter: counter).equatable()
      }
    }
    .font(font)
  }
}

@MainActor private func _withReuse<T>(_ body: () throws -> T) rethrows -> T {
  let previous = _EquatableViewReuse.enabled
  _EquatableViewReuse.enabled = true
  defer { _EquatableViewReuse.enabled = previous }
  return try body()
}

@MainActor private func _html(_ tree: FiberTree) -> String {
  StaticHTMLFiberRenderer().renderNode(tree.renderNode)
}

@Suite("EquatableView") @MainActor struct EquatableViewTests {
  @Test func equalRowsSkipTheirBodyAndTheirSubtreeIsNotWalked() {
    _withReuse {
      let counter = _BodyCounter()
      let tree = FiberTree(_CountedList(values: [1, 2, 3], counter: counter), deferLazyCollections: false, startLifecycle: false)
      #expect(counter.count == 3)
      let before = tree.metrics.equatableSubtreesReused
      _ = tree.update(_CountedList(values: [1, 2, 3], counter: counter, header: "changed"))
      #expect(counter.count == 3, "no row body runs again for equal rows")
      #expect(tree.metrics.equatableSubtreesReused - before == 3)
    }
  }

  @Test func aChangedRowRendersAgainAndOnlyThatRow() {
    _withReuse {
      let counter = _BodyCounter()
      let tree = FiberTree(_CountedList(values: [1, 2, 3], counter: counter), deferLazyCollections: false, startLifecycle: false)
      _ = tree.update(_CountedList(values: [1, 20, 3], counter: counter))
      #expect(counter.count == 4, "only the changed row's body runs")
      #expect(_html(tree).contains("value 20"))
      #expect(!_html(tree).contains("value 2<"))
    }
  }

  @Test func anEnvironmentValueTheRowReadMakesItRenderAgain() {
    _withReuse {
      let counter = _BodyCounter()
      let tree = FiberTree(_CountedList(values: [1, 2], counter: counter, font: .body), deferLazyCollections: false, startLifecycle: false)
      let before = _html(tree)
      _ = tree.update(_CountedList(values: [1, 2], counter: counter, font: .title))
      #expect(counter.count == 4, "a changed font reaches equal rows")
      #expect(_html(tree) != before)
      // The same font again: equal rows are reused once more.
      _ = tree.update(_CountedList(values: [1, 2], counter: counter, font: .title))
      #expect(counter.count == 4)
    }
  }

  @Test func contentThatReadsStateIsNeverReusedAndStaysReactive() {
    struct Reading: View, Equatable {
      let id: Int
      @State private var taps = 0
      nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
      var body: some View { Button("taps \(taps)") { taps += 1 } }
    }
    struct Root: View {
      var body: some View { VStack { Reading(id: 1).equatable() } }
    }
    _withReuse {
      let tree = FiberTree(Root(), deferLazyCollections: false, startLifecycle: false)
      tree.setExternalInvalidationHandler({}, deferUpdates: true)
      tree.dispatch(event: "click")
      _ = tree.renderNode
      #expect(_html(tree).contains("taps 1"))
      _ = tree.update(Root())
      tree.dispatch(event: "click")
      _ = tree.renderNode
      #expect(_html(tree).contains("taps 2"))
    }
  }

  @Test func ownersInsideAReusedRowStayMounted() {
    struct Inner: View {
      var body: some View { Text("inner") }
    }
    struct Row: View, Equatable {
      let id: Int
      nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
      var body: some View { VStack { AnyView(Inner()) } }
    }
    struct Root: View {
      let tick: Int
      var body: some View { VStack { Text("tick \(tick)"); Row(id: 1).equatable() } }
    }
    func owners(_ fiber: Fiber) -> [UInt64] {
      (fiber.renderOwnerToken.map { [$0] } ?? []) + fiber.children.flatMap(owners)
    }
    _withReuse {
      let tree = FiberTree(Root(tick: 0), deferLazyCollections: false, startLifecycle: false)
      tree.setExternalInvalidationHandler({}, deferUpdates: true)
      _ = tree.update(Root(tick: 1))
      _ = tree.update(Root(tick: 2))
      let registry = tree._ownerRegistryForTesting
      for token in owners(tree.root) {
        #expect(registry._contains(token), "every mounted owner keeps its registry entry")
      }
      #expect(_html(tree).contains("tick 2") && _html(tree).contains("inner"))
    }
  }

  @Test func reuseOffRendersTheSameTree() {
    let counter = _BodyCounter()
    let reused = _withReuse { () -> String in
      let tree = FiberTree(_CountedList(values: [1, 2, 3], counter: counter), deferLazyCollections: false, startLifecycle: false)
      _ = tree.update(_CountedList(values: [1, 5, 3], counter: counter))
      return _html(tree)
    }
    let previous = _EquatableViewReuse.enabled
    _EquatableViewReuse.enabled = false
    defer { _EquatableViewReuse.enabled = previous }
    let tree = FiberTree(_CountedList(values: [1, 2, 3], counter: counter), deferLazyCollections: false, startLifecycle: false)
    _ = tree.update(_CountedList(values: [1, 5, 3], counter: counter))
    #expect(_html(tree) == reused)
  }
}
