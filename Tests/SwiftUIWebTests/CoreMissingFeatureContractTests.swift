import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite(.processGlobalState)
@MainActor
struct CoreMissingFeatureContractTests {
  private struct PrimitiveLabelStyle: PrimitiveButtonStyle {
    @MainActor func makeBody(configuration: Configuration) -> some View {
      configuration.label
    }
  }

  @Test
  @MainActor func primitiveButtonStyleShareLinkInitializersAndControlEnvironmentStayComposable() throws {
    let styleValues: [ButtonStyleValue] = [
      .automatic, .plain, .bordered, .borderedProminent, .borderless, .link
    ]
    #expect(styleValues.map(\.rawValue) == ["automatic", "plain", "bordered", "bordered-prominent", "borderless", "link"])

    let view = VStack {
      Button("Styled action") {}.buttonStyle(PrimitiveLabelStyle())
      ShareLink(item: "https://example.test")
      ShareLink(
        item: "https://example.test/details",
        subject: Text("Details"),
        message: Text("Read this")
      )
      ShareLink<Text>(item: "unavailable").disabled(true)
      ShareLink(item: "unavailable", subject: Text("Unavailable")) {
        Text("Custom unavailable")
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .tint(.purple)
    }
    let tree = FiberTree(view)
    let buttons = allNodes(tree.renderNode).filter { $0.attributes["data-control-kind"] == "share-link" }
    #expect(buttons.count == 4)
    #expect(buttons[0].attributes["data-share-item"] == "https://example.test")
    #expect(buttons[0].attributes["aria-label"] == "Share")
    #expect(buttons[1].attributes["data-share-subject"] == "Details")
    #expect(buttons[1].attributes["data-share-message"] == "Read this")
    #expect(buttons[2].attributes["disabled"] == "disabled")
    #expect(buttons[3].attributes["data-button-style"] == "bordered-prominent")
    #expect(buttons[3].attributes["data-control-size"] == "large")
    #expect(buttons[3].attributes["data-tint"] == Color.purple.cssValue)
    #expect(buttons[3].styles["--tint-color"] == Color.purple.cssValue)

    let primitive = try #require(findNode(tree.renderNode) {
      $0.attributes["data-button-style-custom"] == "true"
    })
    #expect(primitive.attributes["data-button-style-custom"] == "true")
  }

  @Test
  @MainActor func shareLinkDispatchesItsPayloadAndTextConveniencesRenderTheirDefaultLabel() throws {
    var shared: (String, String?, String?)?
    ShareRuntime.install { item, subject, message in
      shared = (item, subject, message)
    }
    defer { ShareRuntime.install(nil) }

    let simple: ShareLink<Text> = ShareLink(item: "https://example.test/simple")
    let detailed: ShareLink<Text> = ShareLink(
      item: "https://example.test/detailed",
      subject: Text("Subject"),
      message: Text("Message")
    )
    let tree = FiberTree(VStack { simple; detailed })
    let shareButtons = allNodes(tree.renderNode).filter {
      $0.attributes["data-control-kind"] == "share-link"
    }
    #expect(shareButtons.map { $0.attributes["aria-label"] } == ["Share", "Share"])
    #expect(shareButtons[0].children.first?.text == "Share")
    #expect(shareButtons[1].attributes["data-share-subject"] == "Subject")
    #expect(shareButtons[1].attributes["data-share-message"] == "Message")

    tree.dispatch(event: "click", on: shareButtons[1])
    #expect(shared?.0 == "https://example.test/detailed")
    #expect(shared?.1 == "Subject")
    #expect(shared?.2 == "Message")
  }

  @Test
  @MainActor func safeAreaInsetEdgesAndAccessibilityTraitRemovalProduceNativeSemantics() throws {
    let tree = FiberTree(
      VStack {
        Text("Leading inset").safeAreaInset(edge: .leading, spacing: 4) { Text("Menu") }
        Text("Trailing inset").safeAreaInset(edge: .trailing) { Text("Inspector") }
        Text("Fallback inset").safeAreaInset(edge: .bottom) { Text("Bottom") }
        Text("Link, not button")
          .accessibilityAddTraits([.isButton, .isLink, .isHeader])
          .accessibilityRemoveTraits([.isButton, .isHeader])
      }
    )

    let insets = allNodes(tree.renderNode).filter { $0.attributes["data-safe-area-edge"] != nil }
    #expect(insets.map { $0.attributes["data-safe-area-edge"] } == ["leading", "trailing", "bottom"])
    #expect(insets[0].styles["flex-direction"] == "row-reverse")
    #expect(insets[1].styles["flex-direction"] == "row")
    #expect(insets[2].styles["flex-direction"] == "column")
    #expect(insets[0].attributes["data-layout-gap"] == "4.0")

    let accessible = try #require(findNode(tree.renderNode) { $0.text == "Link, not button" })
    #expect(accessible.attributes["role"] == "link")
    #expect(accessible.attributes["aria-level"] == nil)
  }

  @Test
  @MainActor func canvasConveniencesExposeDefaultAndCustomShapePathIdentity() {
    struct EmptyShape: Shape {}

    var context = GraphicsContext()
    context.fill(Rectangle(), with: GraphicsContext.Shading.white)
    context.stroke(Circle(), with: GraphicsContext.Shading.black)
    context.fill(Ellipse(), with: GraphicsContext.Shading.clear)
    #expect(context.opacity == 1)
    #expect(context.blendMode == .normal)

    let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
    let path = Path(rect)
    #expect(path.path(in: rect) == path)
    #expect(EmptyShape().path(in: rect).isEmpty)
  }

  private func allNodes(_ node: _RenderNode) -> [_RenderNode] {
    [node] + node.children.flatMap(allNodes)
  }

  private func findNode(_ node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> _RenderNode? {
    if predicate(node) { return node }
    for child in node.children {
      if let match = findNode(child, where: predicate) { return match }
    }
    return nil
  }
}
