import Testing
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// Several `onChange` modifiers on one view observe their values
/// independently, and typed task identities restart `.task(id:)` for any
/// Equatable value (enums without raw values, structs) — also in Embedded
/// Swift, where values cannot be described by reflection.
@Suite
@MainActor
struct StackedOnChangeTests {
  enum Genre: Hashable { case drama, comedy }
  struct WorkID: Hashable { let raw: Int }

  final class Log: @unchecked Sendable { var entries: [String] = [] }

  private struct Probe: View {
    let genre: Genre
    let optional: Genre?
    let work: WorkID
    let selection: Set<Int>
    let log: Log
    var body: some View {
      Text("probe")
        .onChange(of: genre) { old, new in log.entries.append("genre \(old == .drama ? "d" : "c")>\(new == .drama ? "d" : "c")") }
        .onChange(of: optional) { _, _ in log.entries.append("optional") }
        .onChange(of: work) { log.entries.append("work") }
        .onChange(of: selection) { log.entries.append("selection") }
    }
  }

  @Test
  func stackedOnChangeModifiersObserveTheirOwnValues() {
    let log = Log()
    let tree = FiberTree(Probe(genre: .drama, optional: nil, work: WorkID(raw: 1), selection: [], log: log), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    #expect(log.entries.isEmpty)
    _ = tree.update(Probe(genre: .comedy, optional: nil, work: WorkID(raw: 1), selection: [], log: log))
    #expect(log.entries == ["genre d>c"])
    _ = tree.update(Probe(genre: .comedy, optional: .drama, work: WorkID(raw: 2), selection: [3], log: log))
    #expect(log.entries == ["genre d>c", "optional", "work", "selection"])
    _ = tree.update(Probe(genre: .comedy, optional: .drama, work: WorkID(raw: 2), selection: [3], log: log))
    #expect(log.entries.count == 4)
  }

  @Test
  func taskIdentityGenerationAdvancesOnlyWhenTheValueChanges() {
    let store = StateStore()
    #expect(store._identityGeneration(key: "t", value: WorkID(raw: 1)) == 0)
    #expect(store._identityGeneration(key: "t", value: WorkID(raw: 1)) == 0)
    #expect(store._identityGeneration(key: "t", value: WorkID(raw: 2)) == 1)
    #expect(store._identityGeneration(key: "t", value: WorkID(raw: 1)) == 2)
    #expect(store._identityGeneration(key: "u", value: Genre.drama) == 0)
    #expect(store._identityGeneration(key: "u", value: Genre.comedy) == 1)
  }
}
