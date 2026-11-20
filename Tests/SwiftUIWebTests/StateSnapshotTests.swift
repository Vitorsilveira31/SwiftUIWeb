// The state snapshot exists in debug builds only (StateSnapshot.swift), and so do its tests.
#if DEBUG
import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

private struct Plain: Equatable { var x = 0 }

private struct Form: View {
  @State private var count = 3
  @State private var name = "Ada"
  @State private var enabled = false
  @State private var ratio = 0.5
  @State private var picked: Int? = nil
  @State private var tags = ["a", "b"]
  @State private var plain = Plain()
  var body: some View {
    VStack {
      Text("count=\(count) name=\(name) enabled=\(enabled ? "yes" : "no") ratio=\(ratio)")
      Text("picked=\(picked.map(String.init) ?? "none") tags=\(tags.joined(separator: "+")) plain=\(plain.x)")
    }
  }
}

/// Removes what the suite's tests install, inside the global-state gate after each test (`ProcessGlobalStateTrait`).
/// A `deinit` would run whenever the instance is released, possibly while the next test holds the gate.
@MainActor private func resetStateSnapshots() {
  _StateSnapshots.enabled = false
  _StateSnapshots.pending.removeAll()
}

/// The values a debug page hands to the page that replaces it (`_StateSnapshots`, StateSnapshot.swift).
@Suite(.serialized, .processGlobalState(tearDown: resetStateSnapshots))
@MainActor
final class StateSnapshotTests {
  init() { _StateSnapshots.enabled = true; _StateSnapshots.pending.removeAll() }
  private func html(_ tree: FiberTree) -> String { tree.renderNode.htmlDescription }

  // MARK: The text form of a value

  @Test func plainValuesHaveATagAndComeBackFromTheirText() {
    #expect(Bool._stateSnapshotTag == "b" && Int._stateSnapshotTag == "i" && Double._stateSnapshotTag == "d" && String._stateSnapshotTag == "s")
    #expect(Bool._stateSnapshotValue(Substring(Bool._stateSnapshotText(true))) == true)
    #expect(Int._stateSnapshotValue(Substring(Int._stateSnapshotText(-42))) == -42)
    #expect(Double._stateSnapshotValue(Substring(Double._stateSnapshotText(0.125))) == 0.125)
    #expect(String._stateSnapshotValue(Substring(String._stateSnapshotText("a\tb\nc"))) == "a\tb\nc")
    #expect(Int._stateSnapshotValue("x") == nil && Bool._stateSnapshotValue("2") == nil)
  }

  @Test func optionalsAndArraysAreMadeOfTheirElements() {
    #expect(Int?._stateSnapshotTag == "?i" && [String]._stateSnapshotTag == "[s" && [Int?]._stateSnapshotTag == "[?i")
    #expect(Int?._stateSnapshotValue(Substring(Int?._stateSnapshotText(nil))) == .some(nil))
    #expect(Int?._stateSnapshotValue(Substring(Int?._stateSnapshotText(7))) == .some(7))
    let words = ["", "a:b", "3:x", "line\nbreak"]
    #expect([String]._stateSnapshotValue(Substring([String]._stateSnapshotText(words))) == words)
    #expect([Int]._stateSnapshotValue(Substring([Int]._stateSnapshotText([]))) == [])
    let nested: [Int?] = [1, nil, 3]
    #expect([Int?]._stateSnapshotValue(Substring([Int?]._stateSnapshotText(nested))) == nested)
    // A text that is not one is refused, not half read.
    #expect([Int]._stateSnapshotValue("2:1") == nil && [Int]._stateSnapshotValue("1:x") == nil && [Int]._stateSnapshotValue("z") == nil)
  }

  @Test func aTypeWithoutATextFormHasNoTag() {
    #expect(Float._stateSnapshotTag.isEmpty && [Float]._stateSnapshotTag.isEmpty && Float?._stateSnapshotTag.isEmpty)
  }

  @Test func theKeyPagesShareLeavesOutTheAddressesOfTypes() {
    #expect(_StateSnapshots.stableKey("40#state-member:981021583:type-2061008@type-2034744") == "40#state-member:981021583:type-@type-")
    #expect(_StateSnapshots.stableKey("root/3#7") == "root/3#7")
    #expect(_StateSnapshots.stableKey("type-12x/type-") == "type-x/type-")
  }

  // MARK: A tree

  @Test func aTreeWritesItsPlainStatesAndTheNextOneStartsFromThem() {
    let first = FiberTree(Form())
    #expect(html(first).contains("count=3 name=Ada enabled=no ratio=0.5"))
    let saved = first._stateSnapshotText()
    // One line per plain state, and none for the state of a type without a text form.
    let lines = saved.split(separator: "\n").map { $0.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false) }
    #expect(lines.count == 6)
    #expect(Set(lines.map { String($0[1]) }) == ["i", "s", "b", "d", "?i", "[s"])

    // What the page would have changed before the reload.
    let edited = lines.map { fields -> String in
      let text: String
      switch fields[1] {
      case "i": text = "41"
      case "s": text = "Grace\\tHopper"
      case "b": text = "1"
      case "d": text = "0.75"
      case "?i": text = "s9"
      default: text = "1:x1:y1:z"
      }
      return fields[0] + "\t" + fields[1] + "\t" + text
    }.joined(separator: "\n")
    _StateSnapshots.load(edited)
    let second = FiberTree(Form())
    #expect(html(second).contains("count=41 name=Grace\tHopper enabled=yes ratio=0.75"))
    #expect(html(second).contains("picked=9 tags=x+y+z plain=0"))
    #expect(_StateSnapshots.pending.isEmpty, "each saved value is taken once")
    // The values are the states' own from then on.
    #expect(second._stateSnapshotText().contains("\ti\t41"))
  }

  @Test func aValueSavedByAnotherTypeOrUnderAnotherKeyIsIgnored() {
    let saved = FiberTree(Form())._stateSnapshotText()
    let wrong = saved.split(separator: "\n").map { line -> String in
      let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
      // Every value claims to be a string, and one more is saved for a state that does not exist.
      return fields[0] + "\ts\tchanged"
    }.joined(separator: "\n") + "\nno-such-state\ti\t5"
    _StateSnapshots.load(wrong)
    let tree = FiberTree(Form())
    #expect(html(tree).contains("count=3 name=changed enabled=no ratio=0.5"))
    #expect(html(tree).contains("picked=none tags=a+b"))
  }

  @Test func nothingIsKeptWhileTheLoopIsOff() {
    _StateSnapshots.enabled = false
    #expect(FiberTree(Form())._stateSnapshotText().isEmpty)
  }
}
#endif
