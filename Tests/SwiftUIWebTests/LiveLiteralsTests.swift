import Testing
@testable @_spi(Renderer) @_spi(Generated) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// A literal type the framework knows nothing about: it takes integer literals and has no live conformance.
private struct Meters: ExpressibleByIntegerLiteral, Equatable {
  var value: Int
  init(integerLiteral value: Int) { self.value = value }
}

private struct Counter: View {
  @State private var count = 0
  var body: some View {
    VStack {
      Text(_live(7, "Title"))
      Button("Add") { count += 1 }
      Text("Count \(count)")
    }
  }
}

/// The values the development loop replaces in a running page (`_live`, `_LiveLiterals`): what the lowering's
/// `live-literals` pass writes must mean the literal until another value arrives, and that value afterwards.
@Suite(.serialized, .processGlobalState)
@MainActor
final class LiveLiteralsTests {
  init() { _LiveLiterals.table.removeAll(); _LiveLiterals.unsupported.removeAll(); _LiveLiterals.unapplied = false; _LiveLiterals.launching = false; _LiveLiterals.startupOnly.removeAll() }
  deinit { _LiveLiterals.table.removeAll(); _LiveLiterals.unsupported.removeAll(); _LiveLiterals.unapplied = false; _LiveLiterals.launching = false; _LiveLiterals.startupOnly.removeAll() }

  @Test func aLiteralIsItselfUntilAValueArrives() {
    #expect(_live(1, "Hi") == "Hi")
    #expect(_live(2, 8) == 8)
    #expect(_live(3, 0.5) == 0.5)
    #expect(_live(4, true))
  }

  @Test func replacementsAreTakenByIdAndKind() {
    #expect(_LiveLiterals._apply("1\ts\tHello there\n2\tn\t12\n3\tn\t0.75\n4\tb\tfalse\n") == 4)
    #expect(_live(1, "Hi") == "Hello there")
    #expect(_live(2, 8) == 12)
    #expect(_live(3, 0.5) == 0.75)
    #expect(!_live(4, true))
    // Another id keeps its literal, and a value of another kind is not used.
    #expect(_live(5, "Other") == "Other")
    #expect(_live(1, 3) == 3)
  }

  @Test func anIntegerIsReadExactlyAndOneTheTypeCannotHoldLeavesTheLiteral() {
    _LiveLiterals._apply("1\tn\t9007199254740993\n2\tn\t18446744073709551615\n3\tn\t300\n4\tn\t2.5")
    let wide: Int64 = _live(1, 1)
    let widest: UInt64 = _live(2, 1)
    let narrow: Int8 = _live(3, 7)
    let whole: Int = _live(4, 7)
    let fraction: Double = _live(4, 7)
    #expect(wide == 9_007_199_254_740_993, "above 2^53, where a Double would round")
    #expect(widest == UInt64.max)
    #expect(narrow == 7, "300 is not an Int8")
    #expect(whole == 7 && fraction == 2.5, "a fraction is a value for a floating-point literal only")
  }

  @Test func aReplacementThePageCannotUseIsReported() {
    // A literal of a type without a live form runs through the fallback, which remembers it.
    let before: Meters = _live(40, 5)
    #expect(before == Meters(integerLiteral: 5))
    #expect(!_LiveLiterals._takeUnapplied())
    _LiveLiterals._apply("40\tn\t9")
    #expect(_LiveLiterals._takeUnapplied(), "the replacement is for a literal the page cannot replace")
    #expect(!_LiveLiterals._takeUnapplied(), "asked once")
    // One that was never run before the replacement arrived is found when it runs.
    _LiveLiterals._apply("41\tn\t9")
    #expect(!_LiveLiterals._takeUnapplied())
    let late: Meters = _live(41, 5)
    #expect(late == Meters(integerLiteral: 5) && _LiveLiterals._takeUnapplied())
    // A number the literal's type cannot hold.
    _LiveLiterals._apply("42\tn\t300")
    let narrow: Int8 = _live(42, 7)
    #expect(narrow == 7 && _LiveLiterals._takeUnapplied())
    // A replacement that is used reports nothing.
    _LiveLiterals._apply("43\tn\t8")
    let fine: Int = _live(43, 7)
    #expect(fine == 8 && !_LiveLiterals._takeUnapplied())
  }

  @Test func aStringCarriesItsEscapes() {
    _LiveLiterals._apply("1\ts\ta\\tb\\nc\\\\d")
    #expect(_live(1, "x") == "a\tb\nc\\d")
  }

  @Test func malformedLinesAreSkipped() {
    #expect(_LiveLiterals._apply("x\ts\tvalue\n1\tn\tnot a number\n1\tq\t3\nonly one field\n2\tn\t4") == 1)
    #expect(_live(2, 1) == 4)
  }

  @Test func theLiteralKeepsTheTypeItsPlaceAsksFor() {
    _LiveLiterals._apply("1\tn\t3\n2\ts\tz\n3\tn\t9")
    let integer: Int = _live(1, 1)
    let float: Float = _live(1, 1)
    let width: CGFloat = _live(1, 1.5)
    let optional: Int? = _live(1, 1)
    let character: Character = _live(2, "a")
    let key: KeyEquivalent = _live(2, "a")
    #expect(integer == 3 && float == 3 && width == 3 && optional == 3)
    #expect(character == "z" && key.character == "z")
    // A type without a live conformance compiles and stays as written.
    let length: Meters = _live(3, 5)
    #expect(length == Meters(integerLiteral: 5))
  }

  @Test func aTextStaysALocalizedKey() {
    // `Text("Title")` is a localized key; the wrapped literal must choose the same initializer.
    LocalizationTable.removeAll()
    LocalizationTable.developmentLanguage = "pt-BR"
    LocalizationTable.preferredLanguage = "en"
    LocalizationTable.register(language: "en", entries: ["Criar obra": .text("Create work")])
    defer { LocalizationTable.removeAll(); LocalizationTable.preferredLanguage = nil; LocalizationTable.developmentLanguage = "en" }
    #expect(Text("Criar obra").value == "Create work")
    #expect(Text(_live(1, "Criar obra")).value == "Create work")
  }

  @Test func aReplacementRendersAgainAndKeepsState() {
    let tree = FiberTree(Counter())
    #expect(tree.renderNode.htmlDescription.contains("Title"))
    _LiveLiterals._apply("7\ts\tRenamed")
    _ = tree._liveLiteralsChanged()
    #expect(tree.renderNode.htmlDescription.contains("Renamed"))
    #expect(!tree.renderNode.htmlDescription.contains("Title"))
  }

  // A literal in the application's scene is built once and kept, so rendering again never runs it: the page reloads.
  @Test func aLiteralBuiltWithTheSceneOutsideARenderNeedsAReload() {
    _LiveLiterals.launching = true
    let scene = Text(_live(40, "Before"))
    _LiveLiterals.launching = false
    _LiveLiterals._apply("40\ts\tAfter")
    #expect(_LiveLiterals._takeUnapplied())
    _ = scene
  }

  @Test func aLiteralInAViewBodyRenderedWhileLaunchingIsApplied() {
    _LiveLiterals.launching = true
    let tree = FiberTree(Counter())
    _LiveLiterals.launching = false
    _LiveLiterals._apply("7\ts\tRenamed")
    #expect(!_LiveLiterals._takeUnapplied(), "the body runs again on the next render")
    _ = tree._liveLiteralsChanged()
    #expect(tree.renderNode.htmlDescription.contains("Renamed"))
  }

  @Test func aLiteralFirstRunAfterLaunchOutsideARenderIsApplied() {
    let action = { _live(41, "Saved") }
    #expect(action() == "Saved")
    _LiveLiterals._apply("41\ts\tStored")
    #expect(!_LiveLiterals._takeUnapplied())
    #expect(action() == "Stored")
  }
}
