import Testing
import SwiftUIWeb

@Suite(.serialized)
@MainActor
struct CoreBuilderContractTests {
  private struct BodyBackedLabel: View {
    let title: String
    var body: some View { Text(title) }
  }

  @Test
  func resultBuilderBranchesArraysAvailabilityAndEmptyContentRenderStably() {
    let empty: EmptyView = ViewBuilder.buildBlock()
    let single: Text = ViewBuilder.buildBlock(Text("single"))
    let first: _ConditionalContent<Text, Text> = ViewBuilder.buildEither(first: Text("first"))
    let second: _ConditionalContent<Text, Text> = ViewBuilder.buildEither(second: Text("second"))
    let optionalValue: _ConditionalContent<Text, EmptyView> = ViewBuilder.buildIf(Text("optional"))
    let optionalEmpty: _ConditionalContent<Text, EmptyView> = ViewBuilder.buildIf(nil)
    let available = ViewBuilder.buildLimitedAvailability(Text("available"))
    let array = ForEach(["array one", "array two"], id: \.self) { Text($0) }

    #expect(FiberTree(empty).renderNode.isEmpty)
    #expect(FiberTree(single).renderNode.text == "single")
    #expect(FiberTree(first).renderNode.text == "first")
    #expect(FiberTree(second).renderNode.text == "second")
    #expect(FiberTree(optionalValue).renderNode.text == "optional")
    #expect(FiberTree(optionalEmpty).renderNode.isEmpty)
    #expect(FiberTree(available).renderNode.text == "available")
    #expect(FiberTree(array).renderNode.children.compactMap(\.text) == ["array one", "array two"])
  }

  @Test
  func groupAndTupleViewsPreserveTheirChildrenAndIdentityPaths() {
    let group = Group {
      Text("group one")
      Text("group two")
    }
    let tuple = TupleView<AnyView>([AnyView(Text("tuple one")), AnyView(Text("tuple two"))])

    let groupHTML = FiberTree(group).renderNode.htmlDescription
    let tupleHTML = FiberTree(tuple).renderNode.htmlDescription
    #expect(groupHTML.contains("group one") && groupHTML.contains("group two"))
    #expect(tupleHTML.contains("tuple one") && tupleHTML.contains("tuple two"))
  }

  @Test
  func viewBuilderSupportsZeroThroughOneHundredDirectChildrenInOrder() {
    let empty: VStack<EmptyView> = VStack {}
    #expect(FiberTree(empty).renderNode.children.isEmpty)

    let single: VStack<Text> = VStack { Text("child 1") }
    #expect(renderedTexts(FiberTree(single).renderNode) == ["child 1"])

    for count in [0, 1, 10, 11, 20, 50, 100] {
      let tree = FiberTree(VariableDirectChildren(count: count))
      let expected = count == 0 ? [] : (1...count).map { "child \($0)" }
      #expect(renderedTexts(tree.renderNode) == expected)
    }

    let ten = FiberTree(VariableDirectChildren(count: 10))
    let eleven = FiberTree(VariableDirectChildren(count: 11))
    let firstTenIdentity = textFiber(named: "child 1", under: ten.root)?.identity
    #expect(firstTenIdentity == textFiber(named: "child 1", under: eleven.root)?.identity)

    let changingTree = FiberTree(VariableDirectChildren(count: 10))
    let firstTenIdentities = (1...10).map { index in
      textFiber(named: "child \(index)", under: changingTree.root)?.identity
    }
    _ = changingTree.update(VariableDirectChildren(count: 11))
    _ = changingTree.renderNode
    #expect(renderedTexts(changingTree.renderNode) == (1...11).map { "child \($0)" })
    for index in 1...10 {
      #expect(textFiber(named: "child \(index)", under: changingTree.root)?.identity == firstTenIdentities[index - 1])
    }

    _ = changingTree.update(VariableDirectChildren(count: 100))
    _ = changingTree.renderNode
    #expect(renderedTexts(changingTree.renderNode) == (1...100).map { "child \($0)" })
    _ = changingTree.update(VariableDirectChildren(count: 50))
    _ = changingTree.renderNode
    #expect(renderedTexts(changingTree.renderNode) == (1...50).map { "child \($0)" })
    for index in 1...10 {
      #expect(textFiber(named: "child \(index)", under: changingTree.root)?.identity == firstTenIdentities[index - 1])
    }
  }

  @Test
  func partialBlocksComposeConditionalsForEachAndNestedContainers() {
    let firstBranch = FiberTree(BuilderCompositionView(useFirstBranch: true))
    let secondBranch = FiberTree(BuilderCompositionView(useFirstBranch: false))

    #expect(renderedTexts(firstBranch.renderNode) == [
      "before", "first branch", "row 1", "overlay 1", "row 2", "overlay 2",
      "row 3", "overlay 3", "middle", "left", "deep one", "deep two", "right", "after"
    ])
    #expect(renderedTexts(secondBranch.renderNode) == [
      "before", "second branch", "row 1", "overlay 1", "row 2", "overlay 2",
      "row 3", "overlay 3", "middle", "left", "deep one", "deep two", "right", "after"
    ])
  }

  private func renderedTexts(_ node: _RenderNode) -> [String] {
    var values: [String] = []
    if node.kind == .text, let text = node.text { values.append(text) }
    for child in node.children {
      values.append(contentsOf: renderedTexts(child))
    }
    return values
  }

  private func textFiber(named text: String, under fiber: Fiber) -> Fiber? {
    if fiber.renderNode.text == text { return fiber }
    for child in fiber.children {
      if let match = textFiber(named: text, under: child) { return match }
    }
    return nil
  }

  private struct VariableDirectChildren: View {
    let count: Int

    var body: some View {
      VStack {
        if count >= 1 { Text("child 1") }
        if count >= 2 { Text("child 2") }
        if count >= 3 { Text("child 3") }
        if count >= 4 { Text("child 4") }
        if count >= 5 { Text("child 5") }
        if count >= 6 { Text("child 6") }
        if count >= 7 { Text("child 7") }
        if count >= 8 { Text("child 8") }
        if count >= 9 { Text("child 9") }
        if count >= 10 { Text("child 10") }
        if count >= 11 { Text("child 11") }
        if count >= 12 { Text("child 12") }
        if count >= 13 { Text("child 13") }
        if count >= 14 { Text("child 14") }
        if count >= 15 { Text("child 15") }
        if count >= 16 { Text("child 16") }
        if count >= 17 { Text("child 17") }
        if count >= 18 { Text("child 18") }
        if count >= 19 { Text("child 19") }
        if count >= 20 { Text("child 20") }
        if count >= 21 { Text("child 21") }
        if count >= 22 { Text("child 22") }
        if count >= 23 { Text("child 23") }
        if count >= 24 { Text("child 24") }
        if count >= 25 { Text("child 25") }
        if count >= 26 { Text("child 26") }
        if count >= 27 { Text("child 27") }
        if count >= 28 { Text("child 28") }
        if count >= 29 { Text("child 29") }
        if count >= 30 { Text("child 30") }
        if count >= 31 { Text("child 31") }
        if count >= 32 { Text("child 32") }
        if count >= 33 { Text("child 33") }
        if count >= 34 { Text("child 34") }
        if count >= 35 { Text("child 35") }
        if count >= 36 { Text("child 36") }
        if count >= 37 { Text("child 37") }
        if count >= 38 { Text("child 38") }
        if count >= 39 { Text("child 39") }
        if count >= 40 { Text("child 40") }
        if count >= 41 { Text("child 41") }
        if count >= 42 { Text("child 42") }
        if count >= 43 { Text("child 43") }
        if count >= 44 { Text("child 44") }
        if count >= 45 { Text("child 45") }
        if count >= 46 { Text("child 46") }
        if count >= 47 { Text("child 47") }
        if count >= 48 { Text("child 48") }
        if count >= 49 { Text("child 49") }
        if count >= 50 { Text("child 50") }
        if count >= 51 { Text("child 51") }
        if count >= 52 { Text("child 52") }
        if count >= 53 { Text("child 53") }
        if count >= 54 { Text("child 54") }
        if count >= 55 { Text("child 55") }
        if count >= 56 { Text("child 56") }
        if count >= 57 { Text("child 57") }
        if count >= 58 { Text("child 58") }
        if count >= 59 { Text("child 59") }
        if count >= 60 { Text("child 60") }
        if count >= 61 { Text("child 61") }
        if count >= 62 { Text("child 62") }
        if count >= 63 { Text("child 63") }
        if count >= 64 { Text("child 64") }
        if count >= 65 { Text("child 65") }
        if count >= 66 { Text("child 66") }
        if count >= 67 { Text("child 67") }
        if count >= 68 { Text("child 68") }
        if count >= 69 { Text("child 69") }
        if count >= 70 { Text("child 70") }
        if count >= 71 { Text("child 71") }
        if count >= 72 { Text("child 72") }
        if count >= 73 { Text("child 73") }
        if count >= 74 { Text("child 74") }
        if count >= 75 { Text("child 75") }
        if count >= 76 { Text("child 76") }
        if count >= 77 { Text("child 77") }
        if count >= 78 { Text("child 78") }
        if count >= 79 { Text("child 79") }
        if count >= 80 { Text("child 80") }
        if count >= 81 { Text("child 81") }
        if count >= 82 { Text("child 82") }
        if count >= 83 { Text("child 83") }
        if count >= 84 { Text("child 84") }
        if count >= 85 { Text("child 85") }
        if count >= 86 { Text("child 86") }
        if count >= 87 { Text("child 87") }
        if count >= 88 { Text("child 88") }
        if count >= 89 { Text("child 89") }
        if count >= 90 { Text("child 90") }
        if count >= 91 { Text("child 91") }
        if count >= 92 { Text("child 92") }
        if count >= 93 { Text("child 93") }
        if count >= 94 { Text("child 94") }
        if count >= 95 { Text("child 95") }
        if count >= 96 { Text("child 96") }
        if count >= 97 { Text("child 97") }
        if count >= 98 { Text("child 98") }
        if count >= 99 { Text("child 99") }
        if count >= 100 { Text("child 100") }
      }
    }
  }

  private struct BuilderCompositionView: View {
    let useFirstBranch: Bool

    var body: some View {
      VStack {
        Text("before")
        if useFirstBranch {
          HStack { Text("first branch") }
        } else {
          ZStack { Text("second branch") }
        }
        ForEach([1, 2, 3], id: \.self) { index in
          ZStack {
            Text("row \(index)")
            Text("overlay \(index)")
          }
        }
        Text("middle")
        HStack {
          Text("left")
          VStack {
            Text("deep one")
            Text("deep two")
          }
          Text("right")
        }
        Text("after")
      }
    }
  }

  @Test
  func typeErasureRendersPrimitiveAndBodyBackedViewsThroughBothInitializers() {
    let valueErased = AnyView(BodyBackedLabel(title: "value erased"))
    let closureErased = AnyView(content: { BodyBackedLabel(title: "closure erased") })

    #expect(FiberTree(valueErased).renderNode.htmlDescription.contains("value erased"))
    #expect(FiberTree(closureErased).renderNode.htmlDescription.contains("closure erased"))
    #expect(FiberTree(AnyView(Text("primitive erased"))).renderNode.htmlDescription.contains("primitive erased"))
  }

  @Test
  func contentBuilderAliasBuildsViewBodiesAndClosures() {
    let body = FiberTree(ContentBuilderBody(includesConditional: true)).renderNode.htmlDescription
    let omitted = FiberTree(ContentBuilderBody(includesConditional: false)).renderNode.htmlDescription
    let closure = FiberTree(buildContent {
      Text("closure first")
      Text("closure second")
    }).renderNode.htmlDescription

    #expect(body.contains("content-builder body"))
    #expect(body.contains("content-builder conditional"))
    #expect(omitted.contains("content-builder body"))
    #expect(!omitted.contains("content-builder conditional"))
    #expect(closure.contains("closure first") && closure.contains("closure second"))
  }

  private struct ContentBuilderBody: View {
    let includesConditional: Bool

    @ContentBuilder
    var body: some View {
      Text("content-builder body")
      if includesConditional {
        Text("content-builder conditional")
      }
    }
  }

  private func buildContent(@ContentBuilder _ content: () -> some View) -> some View {
    content()
  }
}
