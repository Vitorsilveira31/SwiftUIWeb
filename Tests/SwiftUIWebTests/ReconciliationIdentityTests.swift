import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber

/// Regression coverage for the complete semantic identity chain. These tests
/// deliberately exercise Fiber directly: the browser adapter consumes the
/// same structural IDs and event closures at its commit boundary.
@Suite(.serialized)
@MainActor
final class ReconciliationIdentityTests {
  private final class EventBox { var last: Int? }

  private struct StatefulIdentityRow: View {
    let id: String
    @State var count = 0

    var body: some View {
      Button("\(id):\(count)") { count += 1 }
    }
  }

  private struct ConditionalSiblingRoot: View {
    let showsMiddle: Bool

    var body: some View {
      VStack {
        StatefulIdentityRow(id: "before")
        if showsMiddle {
          StatefulIdentityRow(id: "middle")
        }
        StatefulIdentityRow(id: "after")
      }
    }
  }

  private struct ConditionalBranchRoot: View {
    let showsFirst: Bool

    var body: some View {
      VStack {
        if showsFirst {
          StatefulIdentityRow(id: "first branch")
        } else {
          StatefulIdentityRow(id: "second branch")
        }
        StatefulIdentityRow(id: "after branch")
      }
    }
  }

  /// Two `if`s in one builder, as a list's empty-state note before its always-shown field.
  private struct SiblingConditionalsRoot: View {
    let showsNote: Bool
    let showsField = true

    var body: some View {
      VStack {
        if showsNote {
          Text("note")
        }
        if showsField {
          StatefulIdentityRow(id: "field")
        }
      }
    }
  }

  /// A view whose body is one conditional, as a gate that shows a drawer while one is open.
  private struct GatedRow: View {
    @State var isOpen = false

    var body: some View {
      if isOpen {
        StatefulIdentityRow(id: "gated")
      }
    }
  }

  private struct GateHost: View {
    let gate: GatedRow

    var body: some View {
      VStack {
        Text("base").overlay { gate }
      }
    }
  }

  private struct StatefulSheetRoot: View {
    @State private var isPresented = false
    @State private var selectedValue: String?
    @State private var revision = 0

    var body: some View {
      Button("Open stateful sheet") {
        selectedValue = "selected"
        revision += 1
        isPresented = true
      }
      .sheet(isPresented: $isPresented) {
        if let selectedValue {
          Text("\(selectedValue):\(revision)")
        } else {
          Text("missing selection")
        }
      }
    }
  }

  private struct NestedCompositionRoot: View {
    let showsBadge: Bool
    let ids: [String]

    var body: some View {
      VStack {
        HStack {
          Text("header")
          if showsBadge { Text("badge") }
          Group {
            Text("group A")
            Text("group B")
          }
        }
        Group {
          VStack {
            Text("list")
            ForEach(ids, id: \.self) { id in
              HStack {
                Text("row \(id)")
                if id == "B" {
                  Text("special")
                } else {
                  Text("normal")
                }
                Group { StatefulIdentityRow(id: "nested-\(id)") }
              }
            }
            Text("tail")
          }
        }
      }
    }
  }

  private func keyedView(_ ids: [Int], box: EventBox) -> some View {
    ForEach(ids, id: \.self) { id in
      Button("row-\(id)") { box.last = id }
    }
  }

  @Test
  func testReorderInsertRemoveMoveSwapRetainsSemanticFibers() {
    let box = EventBox()
    let tree = FiberTree(keyedView([1, 2, 3, 4], box: box))
    let original = Dictionary(uniqueKeysWithValues: tree.root.children.map { (fiberKeyDescription($0.identity.path.last!), ObjectIdentifier($0)) })

    _ = tree.update(keyedView([4, 2, 5, 1], box: box))
    _expectEqual(tree.root.children.count, 4)
    _expectEqual(ObjectIdentifier(tree.root.children[0]), original["4"])
    _expectEqual(ObjectIdentifier(tree.root.children[1]), original["2"])
    _expectEqual(ObjectIdentifier(tree.root.children[3]), original["1"])
    _expectNil(original["3"].flatMap { id in tree.root.children.first(where: { ObjectIdentifier($0) == id }) })
    _expectTrue(tree.metrics.retainedNodes >= 3)
    _expectGreaterThanOrEqual(tree.metrics.createdNodes, 1)
    _expectGreaterThanOrEqual(tree.metrics.removedNodes, 1)

    tree.dispatch(event: "click", at: tree.root.children[0].identity)
    _expectEqual(box.last, 4, "event closure followed the retained semantic row")
  }

  @Test
  func testDuplicateIDsNeverCreateDuplicateFiberIdentities() {
    let box = EventBox()
    let tree = FiberTree(keyedView([7, 7, 8], box: box))
    let first = tree.root.children.map(\.identity)
    _expectEqual(Set(first).count, first.count)

    _ = tree.update(keyedView([7, 7, 8], box: box))
    let second = tree.root.children.map(\.identity)
    _expectEqual(Set(second).count, second.count)
    _expectEqual(second.count, 3)
    tree.dispatch(event: "click", at: tree.root.children[1].identity)
    _expectEqual(box.last, 7)
  }

  @Test
  func testFiberKeyMatchesSwiftStringCanonicalEquality() {
    let composed = _FiberKey("\u{00E9}")
    let decomposed = _FiberKey("e\u{0301}")
    _expectEqual(composed, decomposed)
    _expectEqual(Set([composed, decomposed]).count, 1)
  }

  @Test
  func testNestedKeyedCollectionsDoNotLeakIdentityAcrossOwners() {
    let box = EventBox()
    func view(_ groups: [[Int]]) -> some View {
      ForEach(Array(groups.enumerated()), id: \.offset) { group in
        ForEach(group.element, id: \.self) { id in
          Button("\(group.offset)-\(id)") { box.last = id }
        }
      }
    }
    let tree = FiberTree(view([[1, 2], [1, 3]]))
    let before = tree.root.children.flatMap(\.children).map(\.identity)
    _expectEqual(Set(before).count, before.count)
    _ = tree.update(view([[1, 3], [1, 2]]))
    let after = tree.root.children.flatMap(\.children).map(\.identity)
    _expectEqual(Set(after).count, after.count)
    _expectNotEqual(before, after, "the outer move changes the path while each inner owner remains scoped")
  }

  @Test
  func testConditionalInsertionAndRemovalKeepSiblingSlotsAndState() {
    let tree = FiberTree(ConditionalSiblingRoot(showsMiddle: false))
    guard let before = statefulButton("before:0", in: tree.root),
          let after = statefulButton("after:0", in: tree.root) else {
      return _fail("the initial conditional siblings should be mounted")
    }
    let beforeIdentity = before.identity
    let afterIdentity = after.identity
    let hiddenSlots = tree.root.children.first?.children ?? []
    _expectEqual(hiddenSlots.count, 3, "the invisible branch keeps its structural slot")
    _expectEqual(hiddenSlots[1].renderNode.kind, .empty)

    tree.dispatch(event: "click", at: beforeIdentity)
    tree.dispatch(event: "click", at: afterIdentity)
    _ = tree.update(ConditionalSiblingRoot(showsMiddle: false))
    _expectNotNil(statefulButton("before:1", in: tree.root))
    _expectNotNil(statefulButton("after:1", in: tree.root))

    _ = tree.update(ConditionalSiblingRoot(showsMiddle: true))
    guard let visibleMiddle = statefulButton("middle:0", in: tree.root),
          let visibleAfter = statefulButton("after:1", in: tree.root) else {
      return _fail("inserting the middle branch should not replace its following sibling")
    }
    _expectNotEqual(visibleMiddle.identity, afterIdentity)
    _expectEqual(visibleAfter.identity, afterIdentity)
    _expectEqual(statefulButton("before:1", in: tree.root)?.identity, beforeIdentity)

    _ = tree.update(ConditionalSiblingRoot(showsMiddle: false))
    guard let removedAfter = statefulButton("after:1", in: tree.root) else {
      return _fail("removing the middle branch must retain the following sibling state")
    }
    _expectEqual(removedAfter.identity, afterIdentity)
    _expectEqual(statefulButton("before:1", in: tree.root)?.identity, beforeIdentity)
    _expectFalse(tree.root.renderNode.htmlDescription.contains("middle:"))
  }

  @Test
  func testSiblingConditionalsKeepTheirOwnIdentity() {
    let tree = FiberTree(SiblingConditionalsRoot(showsNote: false))
    guard let field = statefulButton("field:0", in: tree.root) else {
      return _fail("the second conditional should mount")
    }
    let identity = field.identity
    tree.dispatch(event: "click", at: identity)
    _ = tree.update(SiblingConditionalsRoot(showsNote: false))
    // The first conditional is taken now, as the second one is: each is still its own view, so the field keeps its
    // fiber, and with it its state and the structural ID its event route is keyed by.
    for showsNote in [true, false, true] {
      _ = tree.update(SiblingConditionalsRoot(showsNote: showsNote))
      guard let current = statefulButton("field:1", in: tree.root) else {
        return _fail("the field must keep its state when the conditional before it changes")
      }
      _expectTrue(current === field)
      _expectEqual(current.identity, identity)
      _expectTrue(tree._isStructuralNodeLive(field.structuralID))
      _expectEqual(tree.root.renderNode.htmlDescription.contains("note"), showsNote)
    }
  }

  @Test
  func testTargetedPassThatTakesTheOtherBranchMountsTheBranchUnderItsIdentity() {
    let gate = GatedRow()
    let host = GateHost(gate: gate)
    let tree = FiberTree(host)
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    // Only the gate renders again, and the node it hands back sits under the other branch's key.
    gate.isOpen = true
    _ = tree._drainSubtreeUpdates()
    guard let row = statefulButton("gated:0", in: tree.root) else {
      return _fail("opening the gate should mount its row")
    }
    tree.dispatch(event: "click", at: row.identity)
    // A pass over the whole tree finds the row where the targeted pass put it: the same fiber, with its state and the
    // structural ID its event route is keyed by.
    _ = tree.update(host)
    guard let kept = statefulButton("gated:1", in: tree.root) else {
      return _fail("a later pass over the parent must not replace the row the gate opened")
    }
    _expectTrue(kept === row)
    _expectTrue(tree._isStructuralNodeLive(row.structuralID))
  }

  @Test
  func testIfElseBranchesHaveDistinctStateIdentity() {
    let tree = FiberTree(ConditionalBranchRoot(showsFirst: true))
    guard let first = statefulButton("first branch:0", in: tree.root),
          let after = statefulButton("after branch:0", in: tree.root) else {
      return _fail("the first branch and following stateful sibling should mount")
    }
    let firstIdentity = first.identity
    let firstObject = ObjectIdentifier(first)
    let afterIdentity = after.identity
    tree.dispatch(event: "click", at: firstIdentity)
    _ = tree.update(ConditionalBranchRoot(showsFirst: true))
    _ = tree.renderNode
    _expectNotNil(statefulButton("first branch:1", in: tree.root))

    _ = tree.update(ConditionalBranchRoot(showsFirst: false))
    _ = tree.renderNode
    guard let second = statefulButton("second branch:0", in: tree.root),
          let updatedAfter = statefulButton("after branch:0", in: tree.root) else {
      return _fail("switching branches should mount independent branch state")
    }
    let secondIdentity = second.identity
    let secondObject = ObjectIdentifier(second)
    _expectNotEqual(secondIdentity, firstIdentity)
    _expectEqual(updatedAfter.identity, afterIdentity)
    _expectFalse(tree.root.renderNode.htmlDescription.contains("second branch:1"))

    tree.dispatch(event: "click", at: secondIdentity)
    _ = tree.update(ConditionalBranchRoot(showsFirst: false))
    _expectNotNil(statefulButton("second branch:1", in: tree.root))
    _ = tree.update(ConditionalBranchRoot(showsFirst: true))
    _ = tree.renderNode
    guard let reenteredFirst = statefulButton("first branch:0", in: tree.root) else {
      return _fail("returning to the first branch should create fresh state for its reinserted view")
    }
    _expectEqual(reenteredFirst.identity, firstIdentity)
    _expectNotEqual(ObjectIdentifier(reenteredFirst), firstObject)
    _expectFalse(tree.root.renderNode.htmlDescription.contains("first branch:1"))

    _ = tree.update(ConditionalBranchRoot(showsFirst: false))
    _ = tree.renderNode
    guard let reenteredSecond = statefulButton("second branch:0", in: tree.root) else {
      return _fail("returning to the second branch should not recover its removed state")
    }
    _expectEqual(reenteredSecond.identity, secondIdentity)
    _expectNotEqual(ObjectIdentifier(reenteredSecond), secondObject)
    _expectFalse(tree.root.renderNode.htmlDescription.contains("second branch:1"))
  }

  @Test
  func testMultipleStateValuesReachConditionallyInsertedPresentationContent() {
    let tree = FiberTree(StatefulSheetRoot())
    _expectFalse(tree.root.renderNode.htmlDescription.contains("selected:1"))

    tree.dispatch(event: "click")
    let html = tree.renderNode.htmlDescription
    _expectTrue(html.contains("selected:1"), "the selected value and revision should be visible in the newly presented branch")
    _expectFalse(html.contains("missing selection"), "the new branch must not capture an earlier nil state value")
  }

  @Test
  func testForEachStateFollowsIDsThroughReorderAndEdgeAndMiddleEdits() {
    let tree = FiberTree(keyedStatefulRows(["A", "B", "C"]))
    guard let initialB = statefulButton("B:0", in: tree.root) else {
      return _fail("ForEach should mount the B row")
    }
    let bIdentity = initialB.identity
    let bObject = ObjectIdentifier(initialB)
    tree.dispatch(event: "click", at: bIdentity)
    _ = tree.update(keyedStatefulRows(["A", "B", "C"]))
    _ = tree.renderNode
    _expectNotNil(statefulButton("B:1", in: tree.root))

    let updates = [
      ["C", "A", "B"],
      ["X", "C", "A", "B"],
      ["X", "C", "Y", "A", "B"],
      ["C", "Y", "A", "B"],
      ["C", "A", "B"]
    ]
    for ids in updates {
      _ = tree.update(keyedStatefulRows(ids))
      let snapshot = tree.renderNode
      let expectedLabels = ids.map { "\($0):\($0 == "B" ? 1 : 0)" }
      for label in expectedLabels {
        _expectTrue(snapshot.htmlDescription.contains(">\(label)</button>"), "rendered snapshot should preserve \(label) after \(ids)")
      }
      guard let retainedB = statefulButton("B:1", in: tree.root) else {
        return _fail("B's state must follow its stable ForEach ID after \(ids)")
      }
      _expectEqual(retainedB.identity, bIdentity)
      _expectEqual(ObjectIdentifier(retainedB), bObject)
      for id in ids where id != "B" {
        _expectNotNil(statefulButton("\(id):0", in: tree.root), "state must remain attached to ForEach ID \(id) after \(ids)")
      }
    }

    tree.dispatch(event: "click", at: bIdentity)
    _ = tree.update(keyedStatefulRows(["C", "A", "B"]))
    let finalSnapshot = tree.renderNode
    _expectNotNil(statefulButton("B:2", in: tree.root))
    _expectTrue(finalSnapshot.htmlDescription.contains("C:0"))
    _expectTrue(finalSnapshot.htmlDescription.contains("A:0"))

    guard let initialA = statefulButton("A:0", in: tree.root) else {
      return _fail("A should remain mounted before its explicit removal")
    }
    let aIdentity = initialA.identity
    tree.dispatch(event: "click", at: aIdentity)
    _ = tree.update(keyedStatefulRows(["C", "A", "B"]))
    _expectNotNil(statefulButton("A:1", in: tree.root))
    _ = tree.update(keyedStatefulRows(["C", "B"]))
    _expectNil(statefulButton("A:1", in: tree.root))
    _ = tree.update(keyedStatefulRows(["C", "A", "B"]))
    guard let reinsertedA = statefulButton("A:0", in: tree.root) else {
      return _fail("reinserting a removed ID should initialize fresh row state")
    }
    _expectEqual(reinsertedA.identity, aIdentity)
    _expectNotEqual(ObjectIdentifier(reinsertedA), ObjectIdentifier(initialA))
  }

  @Test
  func testNestedContainersFlattenConditionalsAndKeyedRowsWithoutIdentityDrift() {
    let tree = FiberTree(NestedCompositionRoot(showsBadge: true, ids: ["A", "B"]))
    guard let groupA = textFiber("group A", in: tree.root),
          let nestedB = statefulButton("nested-B:0", in: tree.root) else {
      return _fail("the nested HStack, Group and ForEach content should render")
    }
    let groupAIdentity = groupA.identity
    let nestedBIdentity = nestedB.identity
    _expectEqual(textValues(in: tree.root.renderNode), [
      "header", "badge", "group A", "group B", "list", "row A", "normal",
      "nested-A:0", "row B", "special", "nested-B:0", "tail"
    ])

    tree.dispatch(event: "click", at: nestedBIdentity)
    _ = tree.update(NestedCompositionRoot(showsBadge: true, ids: ["A", "B"]))
    _ = tree.update(NestedCompositionRoot(showsBadge: false, ids: ["B", "A"]))

    guard let updatedGroupA = textFiber("group A", in: tree.root),
          let updatedNestedB = statefulButton("nested-B:1", in: tree.root) else {
      return _fail("nested siblings and keyed state should survive the outer edits")
    }
    _expectEqual(updatedGroupA.identity, groupAIdentity)
    _expectEqual(updatedNestedB.identity, nestedBIdentity)
    _expectEqual(textValues(in: tree.root.renderNode), [
      "header", "group A", "group B", "list", "row B", "special", "nested-B:1",
      "row A", "normal", "nested-A:0", "tail"
    ])
  }

  private func keyedStatefulRows(_ ids: [String]) -> some View {
    VStack {
      Text("head")
      ForEach(ids, id: \.self) { StatefulIdentityRow(id: $0) }
      Text("foot")
    }
  }

  private func statefulButton(_ label: String, in fiber: Fiber) -> Fiber? {
    if fiber.renderNode.events["click"] != nil && fiber.renderNode.htmlDescription.contains(label) {
      return fiber
    }
    for child in fiber.children {
      if let found = statefulButton(label, in: child) { return found }
    }
    return nil
  }

  private func textFiber(_ text: String, in fiber: Fiber) -> Fiber? {
    if fiber.renderNode.text == text { return fiber }
    for child in fiber.children {
      if let found = textFiber(text, in: child) { return found }
    }
    return nil
  }

  private func textValues(in node: _RenderNode) -> [String] {
    var values: [String] = []
    if node.kind == .text, let text = node.text { values.append(text) }
    for child in node.children { values.append(contentsOf: textValues(in: child)) }
    return values
  }

  @Test
  func testDeterministicIdentityFuzzPrintsSeedAndHistory() {
    let seed: UInt64 = 0x53574946545549
    var random = seed
    var ids = Array(0..<24)
    let box = EventBox()
    let tree = FiberTree(keyedView(ids, box: box))
    var history: [String] = []
    history.reserveCapacity(2_000)

    func next() -> Int {
      random = random &* 6364136223846793005 &+ 1442695040888963407
      return Int((random >> 32) % UInt64.max)
    }
    for step in 0..<2_000 {
      if ids.isEmpty { ids = [next() % 100_000] }
      let op = next() % 5
      switch op {
      case 0:
        let value = next() % 100_000
        let at = next() % (ids.count + 1)
        ids.insert(value, at: at); history.append("\(step):insert(\(value),\(at))")
      case 1 where ids.count > 1:
        let at = next() % ids.count
        let value = ids.remove(at: at); history.append("\(step):remove(\(value),\(at))")
      case 2 where ids.count > 1:
        let from = next() % ids.count, to = next() % ids.count
        let value = ids.remove(at: from); ids.insert(value, at: to); history.append("\(step):move(\(from),\(to))")
      case 3 where ids.count > 1:
        let a = next() % ids.count, b = next() % ids.count
        ids.swapAt(a, b); history.append("\(step):swap(\(a),\(b))")
      default:
        let at = next() % ids.count
        ids[at] = next() % 100_000; history.append("\(step):replace(\(at))")
      }
      _ = tree.update(keyedView(ids, box: box))
      let identities = tree.root.children.map(\.identity)
      if Set(identities).count != identities.count || identities.count != ids.count {
        _fail("identity fuzz failed seed=\(seed) step=\(step) history=\(history.suffix(40))")
        return
      }
      if let first = tree.root.children.first {
        tree.dispatch(event: "click", at: first.identity)
        if box.last != ids[0] {
          _fail("stale handler seed=\(seed) step=\(step) history=\(history.suffix(40))")
          return
        }
      }
    }
  }
}
