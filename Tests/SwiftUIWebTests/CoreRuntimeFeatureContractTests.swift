import Testing
import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite(.serialized, .processGlobalState)
@MainActor
struct CoreRuntimeFeatureContractTests {
  @Test
  func buttonStyleConfigurationsPreserveLabelsAndTriggerPrimitiveActions() {
    let label = ButtonStyleConfiguration.Label(body: AnyView(Text("Configured label")))
    let configuration = ButtonStyleConfiguration(role: .destructive, label: label, isPressed: true)
    #expect(configuration.role == .destructive)
    #expect(configuration.isPressed)
    let primitiveConfiguration = PrimitiveButtonStyleConfiguration(
      role: configuration.role,
      label: .init(body: configuration.label.body),
      action: {}
    )
    #expect(StaticHTMLFiberRenderer().render(
      BorderedProminentButtonStyle().makeBody(configuration: primitiveConfiguration)
    ).contains("Configured label"))

    var triggerCount = 0
    let primitive = PrimitiveButtonStyleConfiguration(
      role: .cancel,
      label: .init(body: AnyView(Text("Primitive label"))),
      action: { triggerCount += 1 }
    )
    #expect(primitive.role == .cancel)
    #expect(StaticHTMLFiberRenderer().render(primitive.label).contains("Primitive label"))
    primitive.trigger()
    #expect(triggerCount == 1)
  }

  @Test
  func builtInAndConcreteButtonStylesKeepTheirDeclaredStyleAndLabel() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Group {
          Button("Automatic") {}.buttonStyle(.automatic)
          Button("Plain token") {}.buttonStyle(.plain)
          Button("Bordered token") {}.buttonStyle(.bordered)
          Button("Prominent token") {}.buttonStyle(.borderedProminent)
          Button("Borderless token") {}.buttonStyle(.borderless)
          Button("Link token") {}.buttonStyle(.link)
        }
        Group {
          Button("Default concrete") {}.buttonStyle(DefaultButtonStyle())
          Button("Plain concrete") {}.buttonStyle(PlainButtonStyle())
          Button("Bordered concrete") {}.buttonStyle(BorderedButtonStyle())
          Button("Prominent concrete") {}.buttonStyle(BorderedProminentButtonStyle())
          Button("Borderless concrete") {}.buttonStyle(BorderlessButtonStyle())
          Button("Link concrete") {}.buttonStyle(LinkButtonStyle())
        }
      }
    )

    #expect(html.contains("data-button-style=\"automatic\""))
    #expect(html.contains("data-button-style=\"plain\""))
    #expect(html.contains("data-button-style=\"bordered\""))
    #expect(html.contains("data-button-style=\"bordered-prominent\""))
    #expect(html.contains("data-button-style=\"borderless\""))
    #expect(html.contains("data-button-style=\"link\""))
    #expect(html.contains("Default concrete"))
    #expect(html.contains("Prominent concrete"))
  }

  @Test
  func scrollPositionAndProxyPublishRequestsWithAnOwnerScope() throws {
    var position = ScrollPosition(id: 2, anchor: .center)
    position.scrollTo(id: "selected")
    #expect(position._idDescription == "selected")
    #expect(position.anchor == .center)
    position.scrollTo(edge: .bottom)
    #expect(position._idDescription == nil)
    #expect(position.anchor == .bottom)

    var request: (String, UnitPoint?)?
    ScrollViewRuntime.install { id, anchor in request = (id, anchor) }
    defer { ScrollViewRuntime.install(nil) }

    let tree = FiberTree(
      ScrollViewReader { proxy in
        Button("Jump") { proxy.scrollTo("destination", anchor: .top) }
      }
    )
    tree.dispatch(event: "click")
    #expect(request?.0 == "destination")
    #expect(request?.1 == .top)
    #expect(ScrollViewRuntime._consumeLastRequest()?.0 == "destination")
    #expect(ScrollViewRuntime._consumeLastScope()?.hasSuffix("/reader") == true)
    #expect(ScrollViewRuntime._consumeLastRequest()?.0 == nil)
    #expect(ScrollViewRuntime._consumeLastScope() == nil)
  }

  @Test
  func refreshActionsAreAwaitableAndRefreshEventsRunTheInstalledAction() async throws {
    // SwiftUI's refresh action is @Sendable, so the count lives in a reference type.
    final class RefreshCount: @unchecked Sendable {
      var value = 0
    }
    let calls = RefreshCount()
    let action = RefreshAction { calls.value += 1 }
    await action()
    #expect(calls.value == 1)

    let expectation = _makeExpectation(description: "refresh handler")
    let tree = FiberTree(Text("Pull to refresh").refreshable {
      calls.value += 1
      expectation.fulfill()
    })
    #expect(tree.renderNode.attributes["data-refreshable"] == "true")
    tree.dispatch(event: "refresh")
    await _fulfillment(of: [expectation], timeout: 1)
    #expect(calls.value == 2)
  }

  @Test
  func shareRuntimeReceivesItemAndMetadataFields() throws {
    var received: (String, String?, String?)?
    ShareRuntime.install { item, subject, message in received = (item, subject, message) }
    defer { ShareRuntime.install(nil) }

    let tree = FiberTree(
      ShareLink(item: "https://example.test", subject: Text("Subject"), message: Text("Read this")) {
        Text("Share page")
      }
    )
    let button = try #require(tree.findNode(withEvent: "click"))
    tree.dispatch(event: "click", on: button)
    #expect(received?.0 == "https://example.test")
    #expect(received?.1 == "Subject")
    #expect(received?.2 == "Read this")

    let simple = FiberTree(ShareLink(item: "https://example.test/simple") {
      Text("Share without metadata")
    })
    let simpleButton = try #require(simple.findNode(withEvent: "click"))
    #expect(simpleButton.attributes["data-share-item"] == "https://example.test/simple")
    #expect(simpleButton.attributes["data-share-subject"] == nil)
    #expect(simpleButton.attributes["data-share-message"] == nil)

    let disabled = FiberTree(ShareLink(item: "https://example.test/disabled") {
      Text("Disabled share")
    }.disabled(true))
    let disabledButton = try #require(findNode(disabled.renderNode) {
      $0.attributes["data-control-kind"] == "share-link"
    })
    #expect(disabledButton.attributes["aria-disabled"] == "true")
    #expect(disabledButton.events["click"] == nil)
  }

  @Test
  func textAccessibilityMetadataAndNestedRedactionRemainIndependent() throws {
    let view = VStack {
      Text("Battery").accessibilityValue(Text("78 percent")).accessibilityHint(Text("Current charge"))
      Text("Sensitive")
      Text("Public").unredacted()
    }
    .redacted(reason: .privacy)
    let tree = FiberTree(view)
    let battery = try #require(findNode(tree.renderNode) { $0.attributes["data-a11y-value"] != nil })
    #expect(battery.attributes["aria-valuetext"] == nil)
    #expect(battery.attributes["aria-description"] == "78 percent. Current charge")

    let root = tree.renderNode
    let sensitive = try #require(findNode(root) { $0.text == "Sensitive" })
    let publicText = try #require(findNode(tree.renderNode) { $0.text == "Public" })
    let reasons = try #require(root.attributes["data-redaction-reasons"])
    let busy = try #require(root.attributes["aria-busy"])
    #expect(reasons == "2")
    #expect(busy == "true")
    #expect(sensitive.attributes["data-redaction-reasons"] == nil)
    #expect(publicText.attributes["data-redaction-reasons"] == nil)
  }

  @Test
  func redactedReasonsGetOneClassEachAndUnredactedEndsThem() throws {
    let view = VStack {
      Text("Loading").redacted(reason: .placeholder)
      Text("Card").redacted(reason: .privacy)
      Text("Both").redacted(reason: .placeholder).redacted(reason: .privacy)
      Text("Opted out").redacted(reason: .placeholder).unredacted()
    }
    let root = FiberTree(view).renderNode

    let placeholder = try #require(findNode(root) { $0.attributes["data-redaction-reasons"] == "1" })
    #expect(placeholder.classes.contains("redacted"))
    #expect(placeholder.classes.contains("redacted-placeholder"))
    #expect(!placeholder.classes.contains("redacted-privacy"))

    let privacy = try #require(findNode(root) { $0.attributes["data-redaction-reasons"] == "2" })
    #expect(privacy.classes.contains("redacted-privacy"))
    #expect(!privacy.classes.contains("redacted-placeholder"))

    let both = try #require(findNode(root) { $0.attributes["data-redaction-reasons"] == "3" })
    #expect(both.classes.contains("redacted-placeholder"))
    #expect(both.classes.contains("redacted-privacy"))

    let optedOut = try #require(findNode(root) { $0.classes.contains("unredacted") })
    #expect(!optedOut.classes.contains("redacted"))
    #expect(!optedOut.classes.contains("redacted-placeholder"))
    #expect(optedOut.attributes["data-redaction-reasons"] == nil)
    #expect(optedOut.attributes["aria-busy"] == nil)
  }

  private func findNode(_ node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> _RenderNode? {
    if predicate(node) { return node }
    for child in node.children {
      if let match = findNode(child, where: predicate) { return match }
    }
    return nil
  }
}
