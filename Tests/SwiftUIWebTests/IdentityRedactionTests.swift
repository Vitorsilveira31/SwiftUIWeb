import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// Two different values that hash alike must stay different wherever the framework derives an identity from a hash:
/// environment stamps, view-transition and coordinate-space names, and custom animations. Redacted text must not reach
/// the page under the placeholder reason.
@Suite
@MainActor
struct IdentityRedactionTests {
  /// Equal only by name, with one hash for all names: the collision a hash-only identity cannot tell apart.
  private struct CollidingID: Hashable, Sendable {
    let name: String
    func hash(into hasher: inout Hasher) { hasher.combine(0) }
  }

  private enum CollidingKey: EnvironmentKey {
    static let defaultValue = CollidingID(name: "default")
  }

  private struct PulseAnimation: CustomAnimation, Hashable {
    let tag: String
    func hash(into hasher: inout Hasher) { hasher.combine(0) }
    func animate<V>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? where V: VectorArithmetic {
      time < 1 ? value : nil
    }
  }

  private func html<V: View>(_ view: V) -> String { StaticHTMLFiberRenderer().render(view) }

  @Test
  func environmentStampsOfCollidingValuesDiffer() {
    let id = _storedTypeID(CollidingKey.self)
    var first = EnvironmentValues()
    first[CollidingKey.self] = CollidingID(name: "a")
    var second = EnvironmentValues()
    second[CollidingKey.self] = CollidingID(name: "b")
    #expect(first._stamp(for: id) != second._stamp(for: id))

    // An unchanged value keeps its stamp, so an equatable render can still reuse its output.
    var again = first
    again[CollidingKey.self] = CollidingID(name: "a")
    #expect(again._stamp(for: id) == first._stamp(for: id))
  }

  @Test
  func viewTransitionNamesOfDistinctIDsDiffer() {
    let namespace = Namespace().wrappedValue
    let a = _viewTransitionName(id: CollidingID(name: "a"), in: namespace)
    let b = _viewTransitionName(id: CollidingID(name: "b"), in: namespace)
    let again = _viewTransitionName(id: CollidingID(name: "a"), in: namespace)
    #expect(a != b)
    #expect(a == again)
    #expect(a.hasPrefix("vt-"))
    #expect(a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
  }

  @Test
  func coordinateSpaceKeysOfDistinctIDsDiffer() {
    let a = _coordinateSpaceKey(CollidingID(name: "a"))
    let b = _coordinateSpaceKey(CollidingID(name: "b"))
    #expect(a != b)
    #expect(a == _coordinateSpaceKey(CollidingID(name: "a")))
  }

  @Test
  func coordinateSpaceKeysOutliveManyEnvironmentValues() {
    let key = _coordinateSpaceKey(CollidingID(name: "kept"))
    // More distinct memo stamps than their bounded table holds: the names the page keeps must not move.
    for index in 0 ..< 5_000 { _ = _memoDistinctIDNumber(index) }
    #expect(_coordinateSpaceKey(CollidingID(name: "kept")) == key)
  }

  @Test
  func differentCustomAnimationsWithOneHashAreNotEqual() {
    let first = _CustomAnimationBox(PulseAnimation(tag: "first"))
    let second = _CustomAnimationBox(PulseAnimation(tag: "second"))
    #expect(first == first)
    #expect(first != second)
  }

  @Test
  func placeholderRedactionKeepsTheStringOutOfThePage() {
    let page = html(Text("secret card").redacted(reason: .placeholder))
    #expect(!page.contains("secret"))
    #expect(page.contains("\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}"))
    #expect(page.contains("redacted-placeholder"))
  }

  @Test
  func aRedactedDateKeepsTheDateOutOfThePage() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let page = html(Text(date, style: .date).redacted(reason: .placeholder))
    #expect(!page.contains("data-text-date-style"))
    #expect(!page.contains("1700000000"))
  }

  @Test
  func privacyRedactionHidesOnlyPrivacySensitiveText() {
    let page = html(VStack {
      Text("public title")
      Text("card 4242").privacySensitive()
    }.redacted(reason: .privacy))
    #expect(page.contains("public title"))
    #expect(!page.contains("4242"))
    #expect(html(Text("card 4242").privacySensitive()).contains("4242"))
  }

  @Test
  func unredactedChildShowsItsTextAgain() {
    let page = html(VStack {
      Text("Hidden")
      Text("Shown").unredacted()
    }.redacted(reason: .placeholder))
    #expect(page.contains("Shown"))
    #expect(!page.contains("Hidden"))
  }
}
