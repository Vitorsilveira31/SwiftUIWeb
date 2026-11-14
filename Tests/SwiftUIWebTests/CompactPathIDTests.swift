import Testing
@testable import SwiftUIWeb
import SwiftUIWebHTML
@testable @_spi(Renderer) import SwiftUIWebCore
@testable @_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// The DOM ids and attributes that name an identity path (`data-scroll-id`, `data-presentation-owner-id` and the like)
/// are a short hash of it, not its text: the text is as long as the depth, so the HTML of a deep tree was
/// `O(nodes * depth)` (16 to 18 MB for 1000 nested sheets or forms).
@Suite(.serialized)
@MainActor
struct CompactPathIDTests {
  private func chain(_ depth: Int, registry: _CompactPathIDRegistry) -> [String] {
    var path = _FiberPath()
    var ids: [String] = []
    for level in 0..<depth {
      path.append(_FiberKey(level % 3 == 0 ? "level-\(level)" : String(level)))
      ids.append(path._compactID(in: registry))
    }
    return ids
  }

  @Test
  func theEmptyPathIsRootAndOtherIDsAreShortAtAnyDepth() {
    let registry = _CompactPathIDRegistry()
    #expect(_FiberPath()._compactID(in: registry) == "root")
    let ids = chain(3000, registry: registry)
    #expect(Set(ids).count == ids.count)
    #expect(ids.allSatisfy { $0.count <= 14 })
  }

  @Test
  func theIDIsAFunctionOfThePathAcrossRegistriesAndAskingOrder() {
    let a = _CompactPathIDRegistry()
    let b = _CompactPathIDRegistry()
    // Outer first in one document, only the innermost in the other (the render settles inner levels first).
    let outerFirst = chain(300, registry: a)
    var rebuilt = _FiberPath()
    for index in 0..<300 { rebuilt.append(index % 3 == 0 ? _FiberKey("level-\(index)") : _FiberKey(String(index))) }
    #expect(rebuilt._compactID(in: b) == outerFirst[299])
    #expect(rebuilt._compactID(in: a) == outerFirst[299])
    // The same path built apart gets the same id; one key different anywhere, another.
    var other = _FiberPath()
    for index in 0..<300 { other.append(index == 150 ? _FiberKey("x") : (index % 3 == 0 ? _FiberKey("level-\(index)") : _FiberKey(String(index)))) }
    #expect(other._compactID(in: a) != outerFirst[299])
    // Key boundaries count: `ab/c` is not `a/bc`.
    let split1 = _FiberPath([_FiberKey("ab"), _FiberKey("c")])._compactID(in: a)
    let split2 = _FiberPath([_FiberKey("a"), _FiberKey("bc")])._compactID(in: a)
    #expect(split1 != split2)
  }

  @Test
  func twoDifferentPathsWithTheSameHashNeverShareAnID() {
    let registry = _CompactPathIDRegistry()
    let first = registry.id(hash: 42, fingerprint: 1)
    let second = registry.id(hash: 42, fingerprint: 2)
    let third = registry.id(hash: 42, fingerprint: 3)
    #expect(Set([first, second, third]).count == 3)
    #expect(second == first + "-1" && third == first + "-2")
    // Asking again returns the id the path was given, in any order.
    #expect(registry.id(hash: 42, fingerprint: 3) == third)
    #expect(registry.id(hash: 42, fingerprint: 1) == first)
    #expect(registry.id(hash: 42, fingerprint: 2) == second)
    #expect(registry.id(hash: 43, fingerprint: 1) != first)
  }

  @Test
  func aFullRegistryStartsOverWithoutChangingTheIDs() {
    let registry = _CompactPathIDRegistry(capacity: 8)
    let ids = chain(40, registry: registry)
    let again = chain(40, registry: registry)
    #expect(ids == again)
  }

  private struct Probe: View {
    let depth: Int
    let form: Bool
    var body: some View {
      if depth == 0 {
        Text("leaf")
      } else if form {
        Form { AnyView(Probe(depth: depth - 1, form: true)) }
      } else {
        AnyView(Probe(depth: depth - 1, form: false)).sheet(isPresented: .constant(false)) { Text("s") }
      }
    }
  }

  @Test
  func deepNestedPresentationsAndFormsEmitShortStableIDs() {
    for form in [false, true] {
      let view = Probe(depth: 60, form: form)
      let first = StaticHTMLFiberRenderer().render(view)
      let second = StaticHTMLFiberRenderer().render(view)
      #expect(first == second)
      let name = form ? "data-scroll-id" : "data-presentation-owner-id"
      let ids = first.split(separator: "\(name)=\"").dropFirst().compactMap { $0.split(separator: "\"").first }
      #expect(ids.count == 60)
      #expect(Set(ids).count == ids.count, "\(name) \(ids.prefix(3))")
      #expect(ids.allSatisfy { $0.count <= 24 })
      if form { #expect(first.contains("data-scroll-id=\"form:")) }
    }
  }
}
