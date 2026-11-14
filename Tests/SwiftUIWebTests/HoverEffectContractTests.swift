import Testing
import SwiftUIWeb
@testable @_spi(Renderer) import SwiftUIWebCore
@testable @_spi(Renderer) import SwiftUIWebFeatures

@Suite
@MainActor
struct HoverEffectContractTests {
  @Test
  func environmentCanReadAndOverrideTheInheritedDefaultHoverEffect() {
    var environment = EnvironmentValues()
    #expect(environment.defaultHoverEffect._hoverEffectStyle == "automatic")

    environment.defaultHoverEffect = .highlight

    #expect(environment.defaultHoverEffect._hoverEffectStyle == "highlight")
  }

  @Test
  func defaultHoverOnlyTargetsInteractiveEnabledViews() {
    let tree = FiberTree(
      VStack {
        Text("Section title")
        Button("Action row") {}
        Text("Custom action").onTapGesture {}
        Button("Disabled action") {}.disabled(true)
      }
      .defaultHoverEffect(.highlight)
    )

    var nodes: [_RenderNode] = []
    func collect(_ node: _RenderNode) {
      nodes.append(node)
      node.children.forEach(collect)
    }
    func containsText(_ node: _RenderNode, _ text: String) -> Bool {
      node.text == text || node.children.contains { containsText($0, text) }
    }
    func button(named title: String) -> _RenderNode? {
      nodes.first { node in
        guard case .element(let tag) = node.kind, tag == "button" else { return false }
        return containsText(node, title)
      }
    }
    collect(tree.renderNode)

    let title = nodes.first { $0.text == "Section title" }
    let actionRow = button(named: "Action row")
    let customAction = nodes.first { node in
      !node.events.isEmpty && containsText(node, "Custom action")
    }
    let disabledAction = button(named: "Disabled action")

    _expectNil(title?.attributes["data-hover-effect"])
    _expectEqual(actionRow?.attributes["data-hover-effect"], "highlight")
    _expectEqual(actionRow?.attributes["data-hover-source"], "default")
    #expect(actionRow?.styles["--hover-active-scale"] == "1.0 1.0")
    _expectEqual(customAction?.attributes["data-hover-effect"], "highlight")
    _expectEqual(disabledAction?.attributes["disabled"], "disabled")
    _expectNil(disabledAction?.attributes["data-hover-effect"])
  }

  @Test
  func highlightScalingIsOptInThroughTheCustomEffectClosure() {
    let defaultRow = Button("Default highlight") {}
      .hoverEffect(.highlight)
    let customScale = EmptyHoverEffect().hoverEffect { content, isActive, _ in
      content.scaleEffect(isActive ? 0.98 : 1)
    }
    let scaledRow = Button("Scaled highlight") {}
      .hoverEffect(HoverEffect.highlight.hoverEffect(customScale))

    let defaultNode = FiberTree(defaultRow).renderNode
    let scaledNode = FiberTree(scaledRow).renderNode

    #expect(defaultNode.attributes["data-hover-effect"] == "highlight")
    #expect(defaultNode.styles["--hover-active-scale"] == "1.0 1.0")
    #expect(scaledNode.attributes["data-hover-effect"] == "highlight")
    #expect(scaledNode.styles["--hover-active-scale"] == "0.98 0.98")
    #expect(scaledNode.styles["--hover-rest-scale"] == "1.0 1.0")
  }

  @Test
  func customEffectReceivesGeometryAndSerializesComposedVisualProperties() {
    let row = Button("Hover me") {}
      .frame(width: 120, height: 40)
      .hoverEffect { content, isActive, proxy in
        content
          .scaleEffect(
            x: isActive ? 1.05 : 1,
            y: isActive ? 1.02 : 1,
            anchor: .topLeading
          )
          .offset(x: isActive ? proxy.size.width / 10 : 0, y: isActive ? 4 : 0)
          .rotationEffect(.degrees(isActive ? 9 : 0), anchor: .bottomTrailing)
          .opacity(isActive ? 1 : 0.8)
          .brightness(isActive ? 0.1 : 0)
          .blur(radius: isActive ? 2 : -1)
          .animation(.easeOut(duration: 0.18)) { $0 }
      }

    let node = FiberTree(row).renderNode

    _expectEqual(node.attributes["data-hover-effect"], "custom")
    _expectEqual(node.styles["--hover-active-scale"], "1.05 1.02")
    _expectEqual(node.styles["--hover-active-translate"], "12.0px 4.0px")
    _expectEqual(node.styles["--hover-active-origin"], "100.0% 100.0%")
    _expectEqual(node.styles["--hover-rest-opacity"], "0.8")
    _expectEqual(node.styles["--hover-active-opacity"], "1.0")
    _expectEqual(node.styles["--hover-rest-filter"], "brightness(1.0) blur(0.0px)")
    _expectEqual(node.styles["--hover-active-filter"], "brightness(1.1) blur(2.0px)")
    _expectEqual(node.styles["--hover-duration"], "180ms")
    _expectEqual(node.styles["--hover-timing"], "ease-out")
  }

  @Test
  func explicitlyDisabledCustomEffectNeverEntersItsActivePhase() {
    var observedPhases: [Bool] = []
    let row = Button("No hover") {}
      .hoverEffect(isEnabled: false) { content, isActive, _ in
        observedPhases.append(isActive)
        return content.opacity(isActive ? 1 : 0.75)
      }

    let node = FiberTree(row).renderNode

    _expectEqual(node.attributes["data-hover-effect"], "custom")
    _expectEqual(node.attributes["data-hover-enabled"], "false")
    _expectEqual(observedPhases, [false, false])
    _expectEqual(node.styles["--hover-active-opacity"], "0.75")
  }

  @Test
  func customEffectsComposeStylesGroupsAndDisabledState() throws {
    let namespace = Namespace()
    let group = HoverEffectGroup(
      id: "settings-row", in: namespace.wrappedValue, behavior: .preservesGroup
    )
    let custom = EmptyHoverEffect().hoverEffect(in: group) { content, active, proxy in
      content
        .offset(x: active ? proxy.size.width : 0, y: active ? 3 : 0)
        .rotationEffect(.degrees(active ? 4 : 0), anchor: .topLeading)
        .brightness(active ? 0.2 : 0)
        .blur(radius: active ? 1 : 0)
    }
    #expect(custom.body(content: EmptyHoverEffect())._hoverEffectGroup == group)
    let combined = EmptyHoverEffect().hoverEffect(custom, in: group)
    #expect(combined._hoverEffectStyle == "empty")
    let node = FiberTree(
      Button("Composed") {}.frame(width: 80, height: 32).hoverEffect(combined)
    ).renderNode

    #expect(node.attributes["data-hover-effect"] == "empty")
    #expect(node.attributes["data-hover-group"] == group.id)
    #expect(node.attributes["data-hover-group-behavior"] == "preservesGroup")
    #expect(node.styles["--hover-active-translate"] == "80.0px 3.0px")
    #expect(node.styles["--hover-active-origin"] == "50.0% 50.0%")
    #expect(node.styles["--hover-active-filter"] == "brightness(1.2) blur(1.0px)")

    let disabled = combined.hoverEffectDisabled()
    #expect(disabled.body(content: EmptyHoverEffect())._isHoverEffectDisabled)
    #expect(disabled._isHoverEffectDisabled)
    #expect(disabled._hoverEffectStyle == "empty")
    #expect(disabled._hoverEffectGroup == group)
    let disabledNode = FiberTree(Button("Disabled") {}.hoverEffect(disabled)).renderNode
    #expect(disabledNode.attributes["data-hover-enabled"] == "false")
    #expect(disabledNode.styles["--hover-active-translate"] == "0.0px 0.0px")

    let enabledAgain = combined.hoverEffectDisabled(false)
    #expect(!enabledAgain._isHoverEffectDisabled)
    let enabledNode = FiberTree(Button("Enabled again") {}.hoverEffect(enabledAgain)).renderNode
    #expect(enabledNode.attributes["data-hover-enabled"] == "true")
  }

  @Test
  func hoverEffectGroupInitializersAndValueBodiesKeepStableIdentity() {
    let namespace = Namespace()
    let id = namespace.wrappedValue
    let namespaced = HoverEffectGroup(id, behavior: .preservesGroup)
    let named = HoverEffectGroup(id: "profile", in: id)
    let unnamed = HoverEffectGroup(id: nil, in: id, behavior: .preservesGroup)

    #expect(namespaced.id == HoverEffectGroup(id).id)
    #expect(namespaced.behavior == .preservesGroup)
    #expect(named.id.hasSuffix(":profile"))
    #expect(unnamed.id.hasSuffix(":"))
    #expect(unnamed.behavior == .preservesGroup)
    #expect(named.behavior == .activatesGroup)
    #expect(HoverEffectGroup.systemOverlays.id == "system-overlays")
    #expect(HoverEffect.highlight._hoverEffectStyle == "highlight")

    let emptyEffect = EmptyHoverEffect()
    let emptyNode = FiberTree(Button("No visual change") {}.hoverEffect(emptyEffect)).renderNode
    #expect(emptyNode.styles["--hover-active-scale"] == "1.0 1.0")

    let grouped = HoverEffect.highlight.hoverEffectGroup(named)
    #expect(grouped.body(content: EmptyHoverEffect())._hoverEffectGroup == named)
    #expect(grouped._hoverEffectStyle == "highlight")
    #expect(!grouped._isHoverEffectDisabled)

    let root = GroupHoverEffect.hoverEffectGroup(id: "profile", in: id)
    #expect(root.body(content: EmptyHoverEffect()).group?.id == named.id)
    #expect(root._hoverEffectStyle == "empty")
    #expect(root._hoverEffectGroup == named)
    #expect(!root._isHoverEffectDisabled)
    let rootNode = FiberTree(Button("Group root") {}.hoverEffect(root)).renderNode
    #expect(rootNode.styles["--hover-active-translate"] == "0.0px 0.0px")
  }

  @Test
  func hoverVisualContentConveniencesSerializeTheirAnimation() {
    let visual = EmptyHoverEffectContent().scaleEffect(0.9, anchor: .bottomTrailing)
      .opacity(0.7)
      .brightness(-0.1)
      .blur(radius: -4)
      .animation(.linear(duration: 0.25)) { $0.offset(x: 2, y: 5) }
    let effect = EmptyHoverEffect().hoverEffect { _, active, _ in
      active ? visual._hoverEffectVisual : EmptyHoverEffectContent().rotationEffect(.degrees(0))._hoverEffectVisual
    }
    let node = FiberTree(Button("Visual") {}.hoverEffect(effect)).renderNode

    #expect(node.styles["--hover-active-scale"] == "0.9 0.9")
    #expect(node.styles["--hover-active-origin"] == "100.0% 100.0%")
    #expect(node.styles["--hover-rest-rotate"] == "0.0rad")
    #expect(node.styles["--hover-active-translate"] == "2.0px 5.0px")
    #expect(node.styles["--hover-active-opacity"] == "0.7")
    #expect(node.styles["--hover-active-filter"] == "brightness(0.9) blur(0.0px)")
    #expect(node.styles["--hover-duration"] == "250ms")
    #expect(node.styles["--hover-timing"] == "linear")
  }

  @Test
  func emptyHoverContentCanApplyFilterConveniencesBeforeErasure() {
    let effect = EmptyHoverEffect().hoverEffect { content, active, _ in
      content
        .brightness(active ? 0.2 : 0)
        .blur(radius: active ? 3 : 1)
    }
    let node = FiberTree(Button("Filtered hover") {}.hoverEffect(effect)).renderNode

    #expect(node.styles["--hover-active-filter"] == "brightness(1.2) blur(3.0px)")
    #expect(node.styles["--hover-rest-filter"] == "brightness(1.0) blur(1.0px)")

    let blurOnly = EmptyHoverEffect().hoverEffect { content, active, _ in
      content.blur(radius: active ? 2 : 1)
    }
    let blurNode = FiberTree(Button("Blurred hover") {}.hoverEffect(blurOnly)).renderNode
    #expect(blurNode.styles["--hover-active-filter"] == "brightness(1.0) blur(2.0px)")
    #expect(blurNode.styles["--hover-rest-filter"] == "brightness(1.0) blur(1.0px)")
  }

  @Test
  func colorFilterEffectsResolveToCSSFilterValuesForBothPhases() {
    let node = FiberTree(
      Button("Tinted") {}.hoverEffect { effect, isActive, _ in
        effect
          .saturation(isActive ? 1.5 : 1)
          .grayscale(isActive ? 0 : 0.5)
          .hueRotation(.radians(isActive ? 1 : 0))
          .contrast(isActive ? 1.2 : 1)
      }
    ).renderNode

    #expect(node.attributes["data-hover-has-filter"] == "true")
    #expect(node.styles["--hover-active-filter"] ==
      "brightness(1.0) blur(0.0px) saturate(1.5) contrast(1.2) hue-rotate(1.0rad) grayscale(0.0) invert(0.0)")
    #expect(node.styles["--hover-rest-filter"]?.contains("grayscale(0.5)") == true)
  }
}

@Suite
@MainActor
struct PointerHoverContractTests {
  @Test
  func pointerStyleIsACSSCursor() {
    let node = FiberTree(Text("Drag").pointerStyle(.grabIdle)).renderNode
    #expect(node.styles["cursor"] == "grab")
  }

  @Test
  func continuousHoverDecodesPositionsAndEnd() {
    var phases: [HoverPhase] = []
    let node = FiberTree(Text("Canvas").onContinuousHover { phases.append($0) }).renderNode
    node.events["continuous-hover-move"]?.valueAction?("12.5,4")
    node.events["continuous-hover-move"]?.valueAction?("garbage")
    node.events["continuous-hover-end"]?.action()
    #expect(phases == [.active(CGPoint(x: 12.5, y: 4)), .ended])
  }
}
