import Testing
@testable import SwiftUIWeb

private func inferredButtonStyle<Style: PrimitiveButtonStyle>(_ style: Style) -> String {
  style._swiftUIWebButtonStyleToken ?? "custom"
}

private func inferredTabViewStyle<Style: TabViewStyle>(_ style: Style) -> String {
  style._swiftUIWebTabViewStyle
}

private func inferredPickerStyle<Style: PickerStyle>(_ style: Style) -> String {
  style._swiftUIWebPickerStyle
}

private func inferredTextFieldStyle<Style: TextFieldStyle>(_ style: Style) -> String {
  style._swiftUIWebTextFieldStyle
}

@Suite
@MainActor
struct CoreCompatibilitySurfaceTests {
  @Test
  func compatibilityStyleValuesAndFloatOverloadsPreserveTheirSemanticValues() {
    #expect([
      inferredButtonStyle(.automatic), inferredButtonStyle(.plain),
      inferredButtonStyle(.bordered), inferredButtonStyle(.borderedProminent),
      inferredButtonStyle(.borderless), inferredButtonStyle(.link)
    ] == ["automatic", "plain", "bordered", "bordered-prominent", "borderless", "link"])
    #expect([
      inferredTabViewStyle(.automatic), inferredTabViewStyle(.sidebarAdaptable)
    ] == ["automatic", "sidebar-adaptable"])
    #expect([
      inferredPickerStyle(.automatic), inferredPickerStyle(.inline),
      inferredPickerStyle(.menu), inferredPickerStyle(.segmented),
      inferredPickerStyle(.navigationLink), inferredPickerStyle(.palette)
    ] == ["automatic", "inline", "menu", "segmented", "navigation-link", "palette"])
    #expect([
      inferredTextFieldStyle(.automatic), inferredTextFieldStyle(.plain),
      inferredTextFieldStyle(.roundedBorder)
    ] == ["automatic", "plain", "rounded-border"])
    let automaticDatePickerStyle: DefaultDatePickerStyle = .automatic
    let compactDatePickerStyle: CompactDatePickerStyle = .compact
    let graphicalDatePickerStyle: GraphicalDatePickerStyle = .graphical
    let wheelDatePickerStyle: WheelDatePickerStyle = .wheel
    let fieldDatePickerStyle: FieldDatePickerStyle = .field
    let stepperDatePickerStyle: StepperFieldDatePickerStyle = .stepperField
    let datePickerStyleAliases = [
      automaticDatePickerStyle._swiftUIWebDatePickerStyle,
      compactDatePickerStyle._swiftUIWebDatePickerStyle,
      graphicalDatePickerStyle._swiftUIWebDatePickerStyle,
      wheelDatePickerStyle._swiftUIWebDatePickerStyle,
      fieldDatePickerStyle._swiftUIWebDatePickerStyle,
      stepperDatePickerStyle._swiftUIWebDatePickerStyle
    ]
    #expect(datePickerStyleAliases == [
      "automatic", "compact", "graphical", "wheel", "field", "stepperField"
    ])
    let contextualDatePickerStyles = [
      StaticHTMLFiberRenderer().render(Text("Automatic").datePickerStyle(.automatic)),
      StaticHTMLFiberRenderer().render(Text("Compact").datePickerStyle(.compact)),
      StaticHTMLFiberRenderer().render(Text("Graphical").datePickerStyle(.graphical)),
      StaticHTMLFiberRenderer().render(Text("Wheel").datePickerStyle(.wheel)),
      StaticHTMLFiberRenderer().render(Text("Field").datePickerStyle(.field)),
      StaticHTMLFiberRenderer().render(Text("Stepper field").datePickerStyle(.stepperField))
    ]
    let expectedDatePickerStyleNames = [
      "automatic", "compact", "graphical", "wheel", "field", "stepperField"
    ]
    #expect(contextualDatePickerStyles.map { html in
      expectedDatePickerStyleNames.first { html.contains("data-date-picker-style=\"\($0)\"") } ?? "missing"
    } == expectedDatePickerStyleNames)

    #expect(InlinePickerStyle()._swiftUIWebPickerStyle == "inline")
    #expect(MenuPickerStyle()._swiftUIWebPickerStyle == "menu")
    #expect(SegmentedPickerStyle()._swiftUIWebPickerStyle == "segmented")
    #expect(NavigationLinkPickerStyle()._swiftUIWebPickerStyle == "navigation-link")
    #expect(PalettePickerStyle()._swiftUIWebPickerStyle == "palette")
    #expect(PlainTextFieldStyle()._swiftUIWebTextFieldStyle == "plain")
    #expect(RoundedBorderTextFieldStyle()._swiftUIWebTextFieldStyle == "rounded-border")
    #expect(DefaultDatePickerStyle()._swiftUIWebDatePickerStyle == "automatic")
    #expect(GestureState<Int>(initialValue: 9).wrappedValue == 9)

    let html = StaticHTMLFiberRenderer().render(
      VStack(alignment: .leading, spacing: Float(3)) {
        Text("Float frame")
          .frame(width: Float(80), height: Float(24))
          .padding(Edge.Set.top, Float(4))
          .offset(x: Float(2), y: Float(-3))
          .opacity(Float(0.5))
          .cornerRadius(Float(6))
          .border(.blue, width: 1)
      HStack(alignment: .center, spacing: Float(5)) {
        Text("Float range frame")
          .frame(width: 50, height: 20).frame(maxWidth: 80, maxHeight: 30)
        Text("Float maximum frame")
          .frame(maxWidth: 100, maxHeight: 40)
        Text("Float ideal frame")
          .frame(
            minWidth: Float(10), idealWidth: Float(20), maxWidth: Float(90),
            minHeight: Float(5), idealHeight: Float(15), maxHeight: Float(35)
          )
      }
      Text("Float z-index").zIndex(Float(7))
      Text("Float tracking").tracking(Float(1.25))
      Text("Float kerning").kerning(Float(0.5))
        Text("Float typography")
          .baselineOffset(Float(2))
          .lineSpacing(Float(3))
        Text("Styled date")
          .datePickerStyle(GraphicalDatePickerStyle())
          .toolbarBackground(Color.red, for: .navigationBar)
          .toolbarColorScheme(nil, for: .bottomBar)
        Text("Edge toolbar")
          .toolbarBackground(Color.blue, for: .navigationBar)
          .toolbarColorScheme(.dark, for: .bottomBar)
        LazyVStack(alignment: .leading, spacing: Float(2)) { Text("Lazy vertical") }
        LazyHStack(alignment: .top, spacing: Float(2)) { Text("Lazy horizontal") }
      }
    )

    // The frame is a layer of the padding's element (`_SemanticLayers`): its size is in the layer.
    #expect(html.contains("frame-w=80.0"))
    #expect(html.contains("frame-h=24.0"))
    #expect(html.contains("padding-top: 4px"))
    #expect(html.contains("z-index: 7"))
    #expect(html.contains("letter-spacing: 1.25px"))
    #expect(html.contains("letter-spacing: 0.5px"))
    #expect(html.contains("vertical-align: 2px"))
    #expect(html.contains("line-height: calc(1.2em + 3px)"))
    #expect(html.contains("border-radius: 6px"))
    #expect(html.contains("Lazy vertical"))
    #expect(html.contains("Lazy horizontal"))
    #expect(html.contains("data-date-picker-style=\"graphical\""))
    #expect(html.contains("data-toolbar-background=\"\(Color.red.cssValue)\""))
    #expect(html.contains("data-toolbar-color-scheme=\"automatic\""))
    #expect(html.contains("data-toolbar-color-scheme=\"dark\""))
    #expect(html.contains("data-toolbar-background=\"\(Color.blue.cssValue)\""))
    #expect(html.contains("min-width: 10px"))
    #expect(html.contains("width: 100px"))
    #expect(html.contains("data-layout-gap=\"5.0\""))
  }

  @Test
  func gestureStateReadsWithinFiberScopeAndLegacyGestureModifierKeepsMask() {
    struct GestureStateReader: View {
      @GestureState var presses = 0
      var body: some View { Text("presses=\(presses)") }
    }

    let html = FiberTree(GestureStateReader()).renderNode.htmlDescription
    #expect(html.contains("presses=0"))

    var context = _RenderContext()
    let node = _RenderNode.element("button")
    GestureCompatibilityModifier(name: "legacy", mask: .subviews)._apply(to: node, context: &context)
    #expect(node.attributes["data-gesture"] == "legacy")
    #expect(node.attributes["data-gesture-mask"] == "subviews")
    #expect(node.styles["touch-action"] == "manipulation")

    var actions = 0
    let plainPress = FiberTree(Text("Plain press").onLongPressGesture { actions += 1 })
    let plainPressNode = plainPress.renderNode
    plainPress.dispatch(event: "pointerup", on: plainPressNode)
    #expect(actions == 1)
  }

  @Test
  func gestureStateInitializedInsideBodyUsesItsOwningFiberStore() {
    struct ScopedGestureStateReader: View {
      var body: some View {
        let state = GestureState(wrappedValue: 7)
        return Text("gesture-state=\(state.wrappedValue)")
      }
    }

    #expect(FiberTree(ScopedGestureStateReader()).renderNode.htmlDescription.contains("gesture-state=7"))
  }

  @Test
  func visualScrollAndAccessibilityCompatibilityModifiersRetainTheirContract() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Text("Visual filters")
          .brightness(0.2)
          .contrast(1.3)
          .saturation(0.7)
          .grayscale(0.4)
          .hueRotation(.degrees(90))
          .safeAreaPadding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
          .ignoresSafeArea([.container], edges: [.top, .leading])
        Text("Row metadata")
          .navigationBarBackButtonHidden(false)
          .listRowSeparator(.hidden, edges: [.top, .bottom])
          .listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
          .listRowBackground(Text("Row background"))
          .contentMargins(
            .all,
            EdgeInsets(top: 5, leading: 6, bottom: 7, trailing: 8),
            for: .scrollContent
          )
        Text("Scroll settings")
          .contentMargins(12, for: .scrollContent)
          .scrollEdgeEffectHidden(true, for: [.top, .trailing])
          .defaultScrollAnchor(.bottomTrailing)
          .scrollTargetLayout(isEnabled: false)
          .scrollTargetBehavior(.viewAligned)
          .defaultScrollAnchor(.topLeading)
          .dynamicTypeSize(.xxxLarge)
          .toggleStyle(.switch)
          .pickerStyle(.menu)
          .textFieldStyle(.roundedBorder)
          .textContentType(.emailAddress)
          .submitLabel(.send)
          .keyboardType(.numberPad)
          .autocorrectionDisabled(false)
          .labelsHidden()
          .allowsHitTesting(false)
      }
    )

    #expect(html.contains("data-brightness=\"0.2\""))
    #expect(html.contains("data-contrast=\"1.3\""))
    #expect(html.contains("data-saturation=\"0.7\""))
    #expect(html.contains("data-grayscale=\"0.4\""))
    #expect(html.contains("data-hue-rotation=\"1.5707963267948966\""))
    #expect(html.contains("calc(env(safe-area-inset-top, 0px) + 1px)"))
    #expect(html.contains("data-ignores-safe-area=\"true\""))
    #expect(html.contains("data-navigation-back-button-hidden=\"false\""))
    #expect(html.contains("data-list-row-separator=\"hidden\""))
    #expect(html.contains("data-list-row-insets=\"1.0,2.0,3.0,4.0\""))
    #expect(html.contains("data-content-margins-placement=\"scrollContent\""))
    #expect(html.contains("data-scroll-edge-effect-hidden=\"9\""))
    #expect(html.contains("data-default-scroll-anchor=\"0,0\""))
    #expect(html.contains("data-scroll-target-layout=\"false\""))
    #expect(html.contains("data-scroll-target-behavior=\"view-aligned\""))
    #expect(html.contains("data-scroll-position-initial-anchor=\"0,0\""))
    #expect(html.contains("data-dynamic-type-size=\"xxxLarge\""))
    #expect(html.contains("data-toggle-style=\"switch\""))
    #expect(html.contains("data-picker-style=\"menu\""))
    #expect(html.contains("data-text-field-style=\"rounded-border\""))
    #expect(html.contains("autocomplete=\"emailAddress\""))
    #expect(html.contains("data-submit-label=\"send\""))
    #expect(html.contains("data-keyboard-type=\"numberPad\""))
    #expect(html.contains("autocorrect=\"on\""))
    #expect(html.contains("data-labels-hidden=\"true\""))
    #expect(html.contains("data-allows-hit-testing=\"false\""))
  }

  @Test
  func optionalSelectionsVisibilityEventsAndScrollTransitionAreSafe() throws {
    var focused = false
    var longPressCount = 0
    var pressing: [Bool] = []
    var visible = false
    let view = VStack {
      Text("Effects")
        .focused(Binding(get: { focused }, set: { focused = $0 }))
        .onScrollVisibilityChange(threshold: 3) { visible = $0 }
        .scrollTransition(axis: .horizontal) { effect, phase in
          effect.opacity(phase.isIdentity ? 1 : 0.5)
        }
      Text("Press")
        .onLongPressGesture(
          minimumDuration: 0.25,
          maximumDistance: 12,
          perform: { longPressCount += 1 },
          onPressingChanged: { pressing.append($0) }
        )
    }
    let tree = FiberTree(view)
    let focus = try #require(tree.findNode(withEvent: "focus"))
    tree.dispatch(event: "focus", on: focus)
    #expect(focused)
    tree.dispatch(event: "blur", on: focus)
    #expect(!focused)

    let visibility = try #require(tree.findNode(withEvent: "scrollVisibility"))
    tree.dispatch(event: "scrollVisibility", value: "true", on: visibility)
    #expect(visible)
    #expect(visibility.attributes["data-scroll-visibility-threshold"] == "1")
    #expect(visibility.attributes["data-scroll-transition-axis"] == "horizontal")
    #expect(visibility.attributes["data-scroll-transition-identity"] == "opacity=1")

    let press = try #require(tree.findNode(withEvent: "long-press-action"))
    tree.dispatch(event: "long-press-start", on: press)
    tree.dispatch(event: "long-press-end", on: press)
    tree.dispatch(event: "pointerdown", on: press)
    tree.dispatch(event: "pointercancel", on: press)
    tree.dispatch(event: "pointerup", on: press)
    #expect(pressing == [true, false, true, false, false])
    #expect(longPressCount == 1)
    #expect(press.attributes["data-long-press-duration"] == "0.25")
    #expect(press.attributes["data-long-press-distance"] == "12")

    let disabled = FiberTree(Text("Disabled press").onLongPressGesture {}.disabled(true))
    let disabledNode = disabled.renderNode
    #expect(disabledNode.events["long-press-action"] == nil)
    #expect(disabledNode.attributes["data-long-press"] == "true")
  }

  @Test
  func scrollTargetAndPositionEventsDecodeValidIdentifiersAndIgnoreMalformedValues() throws {
    var position: Int?
    var visible: [Int] = []
    let tree = FiberTree(
      Text("Rows")
        .scrollPosition(id: Binding(get: { position }, set: { position = $0 }), anchor: .center)
        .onScrollTargetVisibilityChange(idType: Int.self) { visible = $0 }
    )
    let visibility = try #require(tree.findNode(withEvent: "scrollTargetVisibility"))
    tree.dispatch(event: "scrollTargetVisibility", value: "4,invalid,9", on: visibility)
    #expect(visible == [4, 9])

    let scrollPosition = try #require(tree.findNode(withEvent: "scrollPosition"))
    tree.dispatch(event: "scrollPosition", value: "12", on: scrollPosition)
    #expect(position == 12)
    tree.dispatch(event: "scrollPosition", value: "not-an-integer", on: scrollPosition)
    #expect(position == 12)
  }
}
