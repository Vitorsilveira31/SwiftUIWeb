import Testing
import SwiftUIWeb

@Observable
private final class ExpandableComparisonModel {
  private(set) var isExpanded = false
  private(set) var isLoading = false

  func prepare() {
    isExpanded = true
    isLoading = true
  }

  func dismiss() {
    isExpanded = false
    isLoading = false
  }
}

@Suite(.serialized)
@MainActor
struct ViewBuilderReconciliationTests {
  private enum ReviewTab {
    case overview
    case reviews
  }

  private struct StatefulCounter: View {
    let label: String
    @State private var count = 0

    var body: some View {
      Button("\(label):\(count)") { count += 1 }
    }
  }

  private struct ConditionalInsertionView: View {
    @State private var showMiddle = false

    var body: some View {
      VStack {
        StatefulCounter(label: "before")
        if showMiddle { StatefulCounter(label: "middle") }
        StatefulCounter(label: "after")
        Button(showMiddle ? "Remove middle" : "Insert middle") { showMiddle.toggle() }
      }
    }
  }

  private struct BranchAlternationView: View {
    @State private var useFirstBranch = true

    var body: some View {
      VStack {
        StatefulCounter(label: "before")
        if useFirstBranch {
          StatefulCounter(label: "first")
        } else {
          StatefulCounter(label: "second")
        }
        StatefulCounter(label: "after")
        Button("Switch branch") { useFirstBranch.toggle() }
      }
    }
  }

  private struct NestedCompositionView: View {
    let showMiddle: Bool
    let itemIDs: [String]

    var body: some View {
      VStack {
        StatefulCounter(label: "before")
        Group {
          HStack {
            if showMiddle {
              StatefulCounter(label: "middle")
            } else {
              StatefulCounter(label: "alternate")
            }
            ForEach(itemIDs, id: \.self) { StatefulCounter(label: $0) }
          }
          ZStack {
            Group {
              StatefulCounter(label: "deep-one")
              StatefulCounter(label: "deep-two")
            }
          }
        }
        StatefulCounter(label: "after")
      }
    }
  }

  private struct ErasedObservableBranchView: View {
    @State private var model: ExpandableComparisonModel

    init() {
      _model = State(wrappedValue: ExpandableComparisonModel())
    }

    var body: some View {
      VStack {
        Button(model.isExpanded ? "Hide comparison" : "Compare versions") {
          if model.isExpanded { model.dismiss() } else { model.prepare() }
        }
        if model.isExpanded {
          Text(model.isLoading ? "Previous version loading" : "Previous version loaded")
        }
      }
    }
  }

  private struct LateMountedObservableBranchView: View {
    @State private var selectedTab = ReviewTab.overview

    var body: some View {
      ScrollView {
        VStack {
          Button("Open review") { selectedTab = .reviews }
          switch selectedTab {
          case .overview:
            Text("Overview")
          case .reviews:
            VStack {
              ForEach(["review"], id: \.self) { _ in
                AnyView(ErasedObservableBranchView())
              }
            }
          }
        }
      }
    }
  }

  private struct SwitchingReviewTabsView: View {
    @State private var selectedTab = ReviewTab.overview

    var body: some View {
      ScrollView {
        VStack {
          Button("Open review tab") { selectedTab = .reviews }
          switch selectedTab {
          case .overview:
            VStack {
              Text("Overview")
              ForEach(["review"], id: \.self) { _ in
                AnyView(ErasedObservableBranchView())
              }
            }
          case .reviews:
            VStack {
              Text("Reviews")
              ForEach(["review"], id: \.self) { _ in
                AnyView(ErasedObservableBranchView())
              }
              Text("Review history")
            }
          }
        }
      }
    }
  }

  @Test
  func insertingAndRemovingMiddleConditionalKeepsSurroundingStateAndIdentity() throws {
    let tree = FiberTree(ConditionalInsertionView())
    let beforeIdentity = try #require(counterFiber(for: "before", in: tree)?.identity)
    let afterIdentity = try #require(counterFiber(for: "after", in: tree)?.identity)

    #expect(clickButton(labeled: "before:0", in: tree))
    #expect(clickButton(labeled: "after:0", in: tree))
    #expect(counterLabels(in: tree) == ["before:1", "after:1"])

    #expect(clickButton(labeled: "Insert middle", in: tree))
    #expect(counterLabels(in: tree) == ["before:1", "middle:0", "after:1"])
    #expect(counterFiber(for: "before", in: tree)?.identity == beforeIdentity)
    #expect(counterFiber(for: "after", in: tree)?.identity == afterIdentity)
    let firstMiddle = try #require(counterFiber(for: "middle", in: tree))

    #expect(clickButton(labeled: "middle:0", in: tree))
    #expect(clickButton(labeled: "Remove middle", in: tree))
    #expect(counterLabels(in: tree) == ["before:1", "after:1"])
    #expect(counterFiber(for: "after", in: tree)?.identity == afterIdentity)

    #expect(clickButton(labeled: "Insert middle", in: tree))
    let recreatedMiddle = try #require(counterFiber(for: "middle", in: tree))
    #expect(buttonLabel(in: recreatedMiddle) == "middle:0")
    #expect(ObjectIdentifier(firstMiddle) != ObjectIdentifier(recreatedMiddle))
    #expect(counterFiber(for: "before", in: tree)?.identity == beforeIdentity)
    #expect(counterFiber(for: "after", in: tree)?.identity == afterIdentity)
  }

  @Test
  func alternatingIfElseBranchesKeepsBranchAndNeighborStateSeparate() throws {
    let tree = FiberTree(BranchAlternationView())
    #expect(clickButton(labeled: "before:0", in: tree))
    #expect(clickButton(labeled: "first:0", in: tree))
    #expect(clickButton(labeled: "after:0", in: tree))
    let firstBranch = try #require(counterFiber(for: "first", in: tree))

    #expect(clickButton(labeled: "Switch branch", in: tree))
    let secondBranch = try #require(counterFiber(for: "second", in: tree))
    #expect(firstBranch.identity != secondBranch.identity)
    #expect(counterLabels(in: tree) == ["before:1", "second:0", "after:1"])
    #expect(clickButton(labeled: "second:0", in: tree))
    #expect(clickButton(labeled: "Switch branch", in: tree))
    #expect(counterLabels(in: tree) == ["before:1", "first:0", "after:1"])
    let recreatedFirstBranch = try #require(counterFiber(for: "first", in: tree))
    #expect(ObjectIdentifier(firstBranch) != ObjectIdentifier(recreatedFirstBranch))
  }

  @Test
  func keyedForEachReorderAndInsertRemovePreserveStateByID() throws {
    let tree = FiberTree(ForEach(["A", "B", "C"], id: \.self) {
      StatefulCounter(label: $0)
    })
    #expect(clickButton(labeled: "A:0", in: tree))
    #expect(clickButton(labeled: "B:0", in: tree))
    #expect(clickButton(labeled: "B:1", in: tree))
    #expect(clickButton(labeled: "C:0", in: tree))
    #expect(clickButton(labeled: "C:1", in: tree))
    #expect(clickButton(labeled: "C:2", in: tree))

    var originalIdentities: [String: FiberIdentity] = [:]
    for id in ["A", "B", "C"] {
      originalIdentities[id] = try #require(counterFiber(for: id, in: tree)?.identity)
    }

    updateRows(["C", "A", "B"], in: tree)
    #expect(counterLabels(in: tree) == ["C:3", "A:1", "B:2"])
    expectRetainedIdentities(["A", "B", "C"], original: originalIdentities, in: tree)

    updateRows(["X", "C", "A", "B"], in: tree)
    #expect(counterLabels(in: tree) == ["X:0", "C:3", "A:1", "B:2"])
    updateRows(["X", "C", "Y", "A", "B"], in: tree)
    #expect(counterLabels(in: tree) == ["X:0", "C:3", "Y:0", "A:1", "B:2"])
    updateRows(["C", "Y", "A", "B"], in: tree)
    #expect(counterLabels(in: tree) == ["C:3", "Y:0", "A:1", "B:2"])
    updateRows(["C", "A", "B"], in: tree)
    #expect(counterLabels(in: tree) == ["C:3", "A:1", "B:2"])
    expectRetainedIdentities(["A", "B", "C"], original: originalIdentities, in: tree)
  }

  @Test
  func nestedBuilderFlatteningKeepsOrderAndFibersAcrossBranchAndForEachChanges() throws {
    let tree = FiberTree(NestedCompositionView(showMiddle: true, itemIDs: ["A", "B"]))
    #expect(buttonLabels(in: tree.renderNode) == [
      "before:0", "middle:0", "A:0", "B:0", "deep-one:0", "deep-two:0", "after:0"
    ])

    var retainedIdentities: [String: FiberIdentity] = [:]
    for id in ["before", "A", "B", "deep-one", "deep-two", "after"] {
      retainedIdentities[id] = try #require(counterFiber(for: id, in: tree)?.identity)
    }
    let middle = try #require(counterFiber(for: "middle", in: tree))

    _ = tree.update(NestedCompositionView(showMiddle: false, itemIDs: ["A", "B"]))
    #expect(buttonLabels(in: tree.renderNode) == [
      "before:0", "alternate:0", "A:0", "B:0", "deep-one:0", "deep-two:0", "after:0"
    ])
    #expect(middle.identity != counterFiber(for: "alternate", in: tree)?.identity)

    _ = tree.update(NestedCompositionView(showMiddle: false, itemIDs: ["B", "C", "A"]))
    #expect(buttonLabels(in: tree.renderNode) == [
      "before:0", "alternate:0", "B:0", "C:0", "A:0", "deep-one:0", "deep-two:0", "after:0"
    ])
    expectRetainedIdentities(["before", "A", "B", "deep-one", "deep-two", "after"], original: retainedIdentities, in: tree)
  }

  @Test
  func observableConditionalInsideErasedKeyedChildUpdatesWithoutLosingItsOwner() throws {
    let tree = FiberTree(ForEach(["review"], id: \.self) { _ in
      AnyView(ErasedObservableBranchView())
    })

    #expect(buttonLabels(in: tree.renderNode) == ["Compare versions"])
    #expect(clickButton(labeled: "Compare versions", in: tree))
    #expect(buttonLabels(in: tree.renderNode) == ["Hide comparison"])
    #expect(textValues(in: tree.renderNode).contains("Previous version loading"))
    #expect(clickButton(labeled: "Hide comparison", in: tree))
    #expect(buttonLabels(in: tree.renderNode) == ["Compare versions"])
  }

  @Test
  func lateMountedObservableChildKeepsItsStateInsideNestedConditionalAndForEach() throws {
    let tree = FiberTree(LateMountedObservableBranchView())

    #expect(clickButton(labeled: "Open review", in: tree))
    #expect(buttonLabels(in: tree.renderNode) == ["Open review", "Compare versions"])
    #expect(clickButton(labeled: "Compare versions", in: tree))
    #expect(buttonLabels(in: tree.renderNode) == ["Open review", "Hide comparison"])
    #expect(textValues(in: tree.renderNode).contains("Previous version loading"))
  }

  @Test
  func switchingBranchesWithTheSameKeyedViewCreatesIndependentStateAndActions() throws {
    let tree = FiberTree(SwitchingReviewTabsView())

    #expect(buttonLabels(in: tree.renderNode) == ["Open review tab", "Compare versions"])
    #expect(clickButton(labeled: "Compare versions", in: tree))
    #expect(buttonLabels(in: tree.renderNode) == ["Open review tab", "Hide comparison"])

    #expect(clickButton(labeled: "Open review tab", in: tree))
    #expect(buttonLabels(in: tree.renderNode) == ["Open review tab", "Compare versions"])
    #expect(clickButton(labeled: "Compare versions", in: tree))
    #expect(buttonLabels(in: tree.renderNode) == ["Open review tab", "Hide comparison"])
    #expect(textValues(in: tree.renderNode).contains("Previous version loading"))
  }

  private func updateRows(_ ids: [String], in tree: FiberTree) {
    _ = tree.update(ForEach(ids, id: \.self) { StatefulCounter(label: $0) })
    _ = tree.renderNode
  }

  private func expectRetainedIdentities(
    _ ids: [String],
    original: [String: FiberIdentity],
    in tree: FiberTree,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    for id in ids {
      #expect(
        counterFiber(for: id, in: tree)?.identity == original[id],
        "Fiber identity for \(id) should stay attached to its logical view",
        sourceLocation: sourceLocation
      )
    }
  }

  private func clickButton(labeled label: String, in tree: FiberTree) -> Bool {
    guard let button = buttonFiber(labeled: label, in: tree.root) else { return false }
    tree.dispatch(event: "click", at: button.identity)
    _ = tree.renderNode
    return true
  }

  private func counterFiber(for label: String, in tree: FiberTree) -> Fiber? {
    findButton(in: tree.root) { value in
      guard let separator = value.lastIndex(of: ":") else { return false }
      return String(value[..<separator]) == label
    }
  }

  private func buttonFiber(labeled label: String, in root: Fiber) -> Fiber? {
    findButton(in: root) { $0 == label }
  }

  private func findButton(in fiber: Fiber, matching predicate: (String) -> Bool) -> Fiber? {
    if fiber.renderNode.attributes["data-control-kind"] == "button",
       let label = buttonLabel(in: fiber), predicate(label) {
      return fiber
    }
    for child in fiber.children {
      if let match = findButton(in: child, matching: predicate) { return match }
    }
    return nil
  }

  private func buttonLabel(in fiber: Fiber) -> String? {
    guard fiber.renderNode.attributes["data-control-kind"] == "button" else { return nil }
    return firstText(in: fiber.renderNode)
  }

  private func buttonLabels(in node: _RenderNode) -> [String] {
    if node.attributes["data-control-kind"] == "button", let label = firstText(in: node) {
      return [label]
    }
    return node.children.flatMap(buttonLabels)
  }

  private func textValues(in node: _RenderNode) -> [String] {
    if node.kind == .text, let text = node.text { return [text] }
    return node.children.flatMap(textValues)
  }

  private func counterLabels(in tree: FiberTree) -> [String] {
    buttonLabels(in: tree.renderNode).filter { $0.contains(":") }
  }

  private func firstText(in node: _RenderNode) -> String? {
    if node.kind == .text { return node.text }
    for child in node.children {
      if let text = firstText(in: child) { return text }
    }
    return nil
  }
}
