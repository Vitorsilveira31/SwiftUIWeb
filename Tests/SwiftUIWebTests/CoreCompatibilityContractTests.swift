import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite
@MainActor
struct CoreCompatibilityContractTests {
  private struct SidebarListStyle: ListStyle {
    var _swiftUIWebListStyle: String { "sidebar" }
  }

  private struct ProminentFormStyle: FormStyle {
    var _swiftUIWebFormStyle: String { "prominent" }
  }

  private struct DefaultFormStyle: FormStyle {}
  private struct DefaultListStyle: ListStyle {}
  private struct DefaultDatePickerStyle: DatePickerStyle {}
  private struct DefaultToggleStyle: ToggleStyle {}
  private struct DefaultPickerStyle: PickerStyle {}
  private struct DefaultTextFieldStyle: TextFieldStyle {}

  @Test
  func compatibilityValuesRetainSwiftUIValueSemantics() {
    let quarterTurn = Angle.degrees(90)
    #expect(quarterTurn.radians == .pi / 2)
    #expect((Angle.radians(1) + quarterTurn - Angle.radians(1)).radians == quarterTurn.radians)
    #expect(Angle.zero == .radians(0))

    let safeArea: SafeAreaRegions = [.container, .keyboard]
    #expect(safeArea == .all)
    #expect(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4).trailing == 4)
    #expect(Material.regularMaterial._swiftUIWebCSSValue.contains("color-mix"))

    #expect(GestureMask(rawValue: 1) == .gesture)
    #expect(GestureMask(rawValue: 2) == .subviews)
    #expect(GestureMask(rawValue: 3) == .all)
    #expect(GestureMask(rawValue: 0).isEmpty)

    #expect(GroupedFormStyle()._swiftUIWebFormStyle == "grouped")
    #expect(ProminentFormStyle()._swiftUIWebFormStyle == "prominent")
    #expect(InsetGroupedListStyle()._swiftUIWebListStyle == "insetGrouped")
    #expect(SidebarListStyle()._swiftUIWebListStyle == "sidebar")

    #expect(FieldDatePickerStyle()._swiftUIWebDatePickerStyle == "field")
    #expect(DefaultDatePickerStyle()._swiftUIWebDatePickerStyle == "automatic")
    #expect(CompactDatePickerStyle()._swiftUIWebDatePickerStyle == "compact")
    #expect(GraphicalDatePickerStyle()._swiftUIWebDatePickerStyle == "graphical")
    #expect(WheelDatePickerStyle()._swiftUIWebDatePickerStyle == "wheel")
    #expect(FieldDatePickerStyle()._swiftUIWebDatePickerStyle == "field")
    #expect(StepperFieldDatePickerStyle()._swiftUIWebDatePickerStyle == "stepperField")

    #expect(DynamicTypeSize.accessibility5.isAccessibilitySize)
    #expect(!DynamicTypeSize.xxxLarge.isAccessibilitySize)
    #expect(ContentTransition.numericText(countsDown: true) == ContentTransition.numericText(value: 1))
    #expect(ContentTransition.numericText(countsDown: false) == ContentTransition.numericText(value: 1))
  }

  @Test
  func scrollGeometryDecodingAndEqualityCoverEveryReportedDimension() throws {
    let minimal = try #require(ScrollGeometry._decode("1,2,300,400,200,250,3,4,180,220"))
    #expect(minimal.contentOffset.x == 1)
    #expect(minimal.contentOffset.y == 2)
    #expect(minimal.visibleRect.size.height == 220)
    #expect(minimal.contentInsets == EdgeInsets())

    let complete = try #require(ScrollGeometry._decode("1,2,300,400,200,250,3,4,180,220,5,6,7,8"))
    #expect(complete.contentInsets == EdgeInsets(top: 5, leading: 6, bottom: 7, trailing: 8))
    #expect(complete == ScrollGeometry._decode("1,2,300,400,200,250,3,4,180,220,5,6,7,8"))
    #expect(ScrollGeometry._decode("1,2,3,4,5,6,7,8,9") == nil)
    #expect(ScrollGeometry._decode("1,2,3,4,5,6,7,8,9,nope") == nil)

    let differences = [
      ScrollGeometry(contentOffset: CGPoint(x: 2, y: 2), contentSize: complete.contentSize,
                     containerSize: complete.containerSize, visibleRect: complete.visibleRect,
                     contentInsets: complete.contentInsets),
      ScrollGeometry(contentOffset: complete.contentOffset,
                     contentSize: CGSize(width: 301, height: 400),
                     containerSize: complete.containerSize, visibleRect: complete.visibleRect,
                     contentInsets: complete.contentInsets),
      ScrollGeometry(contentOffset: complete.contentOffset, contentSize: complete.contentSize,
                     containerSize: CGSize(width: 201, height: 250),
                     visibleRect: complete.visibleRect, contentInsets: complete.contentInsets),
      ScrollGeometry(contentOffset: complete.contentOffset, contentSize: complete.contentSize,
                     containerSize: complete.containerSize,
                     visibleRect: CGRect(x: 4, y: 4, width: 180, height: 220),
                     contentInsets: complete.contentInsets),
      ScrollGeometry(contentOffset: complete.contentOffset, contentSize: complete.contentSize,
                     containerSize: complete.containerSize, visibleRect: complete.visibleRect,
                     contentInsets: EdgeInsets(top: 5, leading: 9, bottom: 7, trailing: 8))
    ]
    #expect(differences.allSatisfy { $0 != complete })
    #expect(ScrollTransitionPhase.identity.isIdentity)
    #expect(ScrollTransitionPhase.topLeading.value == -1)
    #expect(ScrollTransitionPhase.bottomTrailing.value == 1)
  }

  @Test
  func visualEffectsComposeAndClampAtTheirPublicBoundary() {
    let effect = EmptyVisualEffect()
      .opacity(1.5)
      .scaleEffect(x: 0.8, y: 0.9)
      .offset(x: 4, y: -2)
      .rotationEffect(.degrees(90))
      .blur(radius: -3)

    #expect(effect._encoded.contains("opacity=1"))
    #expect(effect._encoded.contains("scale(0.8,0.9)"))
    #expect(effect._encoded.contains("translate(4px,-2px)"))
    #expect(effect._encoded.contains("rotate(1.5707963267948966rad)"))
    #expect(effect._encoded.contains("blur(0px)"))
    #expect(EmptyVisualEffect().opacity(-0.5)._encoded == "opacity=0")
    #expect(EmptyVisualEffect().scaleEffect(0.5)._encoded == "transform=scale(0.5,0.5)")
  }

  @Test
  func textAndImageCompatibilityModifiersRenderTheirSemanticValues() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Group {
          Text("weight").fontWeight(.bold)
          Text("design").fontDesign(.monospaced)
          Text("italic").italic()
          Text("upright").italic(false)
          Text("strike").strikethrough(true, color: .red)
          Text("no-strike").strikethrough(false)
          Text("underline").underline(true, color: .blue)
          Text("no-underline").underline(false)
          Text("tracking").tracking(Float(1.25))
          Text("kerning").kerning(0.5)
        }
        Group {
          Text("baseline").baselineOffset(Float(3))
          Text("spacing").lineSpacing(2.0)
          Text("digits").monospacedDigit()
          Text("upper").textCase(.uppercase)
          Text("default case").textCase(nil)
          TextField("Email", text: .constant("a@b.test"))
            .textInputAutocapitalization(.never)
          TextField("Default", text: .constant(""))
            .textInputAutocapitalization(nil)
          Image(systemName: "wifi").resizable(resizingMode: .tile).scaledToFill()
          Image(systemName: "photo").scaledToFit()
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
          Image(systemName: "square").aspectRatio(0, contentMode: .fill)
        }
        Text("ratio").aspectRatio(nil, contentMode: .fill)
      }
    )

    #expect(html.contains("font-weight: 700"))
    #expect(html.contains("font-family: ui-monospace"))
    #expect(html.contains("font-style: italic"))
    #expect(html.contains("font-style: normal"))
    #expect(html.contains("text-decoration-line: line-through"))
    #expect(html.contains("text-decoration-line: none"))
    #expect(html.contains("text-decoration-color:"))
    #expect(html.contains("letter-spacing: 1.25px"))
    #expect(html.contains("vertical-align: 3px"))
    #expect(html.contains("line-height: calc(1.2em + 2px)"))
    #expect(html.contains("font-variant-numeric: tabular-nums"))
    #expect(html.contains("text-transform: uppercase"))
    #expect(html.contains("text-transform: none"))
    #expect(html.contains("data-text-input-autocapitalization=\"never\""))
    #expect(html.contains("data-text-input-autocapitalization=\"sentences\""))
    #expect(html.contains("data-resizing-mode=\"tile\""))
    #expect(html.contains("aspect-ratio: 1.7777777777777777"))
    #expect(html.contains("data-aspect-ratio=\"\""))
    #expect(html.contains("object-fit: cover"))
  }

  @Test
  func scrollToolbarAndFormModifiersPreserveTheirConfiguration() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        List { Text("sidebar row") }
          .listStyle(SidebarListStyle())
        List { Text("plain row") }
          .listStyle(.plain)
        Form { Text("form row") }
          .formStyle(ProminentFormStyle())
        Form { Text("grouped row") }
          .formStyle(.grouped)
        Text("toolbar")
          .toolbar(.hidden, for: .navigationBar)
          .toolbarBackground(.visible, for: .navigationBar)
          .toolbarBackground(Material.thinMaterial, for: .bottomBar)
          .toolbarColorScheme(.dark, for: .tabBar)
          .toolbarRole(.browser)
          .buttonBorderShape(.capsule)
          .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
          .containerRelativeFrame([.horizontal, .vertical], alignment: .leading)
        Text("toolbar placement").toolbar(.visible, for: .navigationBar)
        Text("toolbar edges").toolbar(.automatic, for: .bottomBar)
        ScrollView { Text("scroll owner") }
          .scrollDisabled(true)
          .scrollIndicators(.hidden)
          .scrollContentBackground(.hidden)
          .scrollBounceBehavior(.always)
      }
    )

    #expect(html.contains("data-list-style=\"sidebar\""))
    #expect(html.contains("data-list-style=\"plain\""))
    #expect(html.contains("data-form-style=\"prominent\""))
    #expect(html.contains("data-form-style=\"grouped\""))
    #expect(html.contains("data-toolbar-visibility-navigationbar=\"hidden\""))
    #expect(html.contains("data-toolbar-placement=\"tabBar\""))
    #expect(html.contains("data-toolbar-visibility-navigationbar=\"visible\""))
    #expect(html.contains("data-toolbar-background-visibility=\"visible\""))
    #expect(html.contains("data-toolbar-background=\"color-mix"))
    #expect(html.contains("data-toolbar-color-scheme=\"dark\""))
    #expect(html.contains("data-toolbar-role=\"browser\""))
    #expect(html.contains("data-button-border-shape=\"capsule\""))
    #expect(html.contains("data-scroll-bounce=\"basedOnSize\""))
    #expect(html.contains("data-layout-kind=\"container-relative\""))
    #expect(html.contains("data-scroll-disabled=\"true\""))
    #expect(html.contains("data-scroll-indicators=\"hidden\""))
    #expect(html.contains("data-scroll-content-background=\"hidden\""))
    #expect(html.contains("scrollbar-width: none"))
    #expect(html.contains("overscroll-behavior: none"))
  }

  @Test
  func scrollPositionMetadataPropagatesToTheNestedScrollOwner() throws {
    let tree = FiberTree(
      VStack {
        ScrollView { Text("Target").id("target") }
          .scrollDisabled(true)
          .scrollIndicators(.hidden)
      }
      .scrollPosition(id: .constant("target"), anchor: .center)
    )
    let scrollOwner = try #require(find(tree.renderNode) {
      $0.classes.contains("scroll-view")
    })

    #expect(scrollOwner.attributes["data-scroll-position"] == "true")
    #expect(scrollOwner.attributes["data-scroll-position-id"] == "target")
    #expect(scrollOwner.attributes["data-scroll-position-anchor"] == "0.5,0.5")
    #expect(scrollOwner.attributes["data-scroll-disabled"] == "true")
    #expect(scrollOwner.attributes["data-scroll-indicators"] == "hidden")
    #expect(scrollOwner.styles["overscroll-behavior"] == "none")
    #expect(scrollOwner.styles["scrollbar-width"] == "none")
  }

  @Test
  func safeAreaScrollAndToolbarCompatibilityOverloadsRetainTheirValues() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Image("hero.png").scaledToFill()
        Text("2D transform").rotationEffect(.degrees(30), anchor: .topLeading)
        Text("3D transform")
          .rotation3DEffect(.degrees(15), axis: (x: 0, y: 1, z: 0), anchorZ: 4)
        ScrollView { Text("Scrollable") }
          .contentMargins([.top, .leading], 9, for: .scrollContent)
          .scrollDismissesKeyboard(.interactively)
          .scrollClipDisabled()
          .scrollTargetLayout()
          .scrollTargetBehavior(.paging)
          .scrollEdgeEffectHidden(true, for: .horizontal)
          .defaultScrollAnchor(.bottom)
        Text("Keyboard toolbar")
          .toolbarBackground(.visible, for: ToolbarPlacement.bottomBar)
        Text("Safe area")
          .safeAreaPadding([.top, .trailing], 6)
          .ignoresSafeArea(.keyboard, edges: .bottom)
          .toolbarBackground(.visible, for: ToolbarPlacement.bottomBar)
          .toolbarBackground(Material.regularMaterial, for: ToolbarPlacement.bottomBar)
          .toolbarColorScheme(nil, for: ToolbarPlacement.bottomBar)
          .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
          .toolbarRole(.editor)
          .presentationBackgroundInteraction(.enabled)
      }
    )

    #expect(html.contains("object-fit: cover"))
    #expect(html.contains("rotate(0.5235987755982988rad)"))
    #expect(html.contains("transform-origin: 0.0% 0.0%"))
    #expect(html.contains("rotate3d(0.0, 1.0, 0.0"))
    #expect(html.contains("data-content-margins-placement=\"scrollContent\""))
    #expect(html.contains("data-scroll-dismisses-keyboard=\"interactively\""))
    #expect(html.contains("data-scroll-clip-disabled=\"true\""))
    #expect(html.contains("data-scroll-target-layout=\"true\""))
    #expect(html.contains("data-scroll-target-behavior=\"paging\""))
    #expect(html.contains("data-scroll-edge-effect-hidden="))
    #expect(html.contains("data-scroll-position-initial-anchor=\"0.5,1\""))
    #expect(html.contains("data-ignores-safe-area=\"true\""))
    #expect(html.contains("data-toolbar-background-visibility=\"visible\""))
    #expect(html.contains("data-toolbar-placement=\"bottomBar\""))
    #expect(html.contains("data-toolbar-background="))
    #expect(html.contains("data-toolbar-color-scheme=\"automatic\""))
    #expect(html.contains("data-toolbar-background-visibility=\"hidden\""))
    #expect(html.contains("data-toolbar-role=\"editor\""))
    #expect(html.contains("data-presentation-background-interaction=\"enabled\""))
  }

  @Test
  func scrollEventAdaptersIgnoreInvalidAndDuplicateEvents() throws {
    var singleGeometryValues: [Double] = []
    var phaseChanges: [(ScrollPhase, ScrollPhase, Double)] = []
    var visible: [Bool] = []
    let view = ScrollView {
      VStack {
        Text("geometry").onScrollGeometryChange(for: Double.self, of: { $0.contentOffset.y }) { _, new in
          singleGeometryValues.append(new)
        }
        Text("phase").onScrollPhaseChange { old, new, context in
          phaseChanges.append((old, new, context.geometry.contentOffset.y))
        }
        Text("visibility").onScrollVisibilityChange(threshold: 2) { visible.append($0) }
      }
    }
    let tree = FiberTree(view)
    let geometryNode = try #require(find(tree.renderNode) { $0.events["scrollGeometry"] != nil })
    let phaseNode = try #require(find(tree.renderNode) { $0.events["scrollPhase"] != nil })
    let visibilityNode = try #require(find(tree.renderNode) { $0.events["scrollVisibility"] != nil })

    geometryNode.events["scrollGeometry"]?.valueAction?("bad")
    geometryNode.events["scrollGeometry"]?.valueAction?("0,12,300,800,320,640,0,12,320,640,0,0,0,0")
    geometryNode.events["scrollGeometry"]?.valueAction?("0,12,300,800,320,640,0,12,320,640,0,0,0,0")
    geometryNode.events["scrollGeometry"]?.valueAction?("0,24,300,800,320,640,0,24,320,640,0,0,0,0")
    #expect(singleGeometryValues == [12, 24])

    phaseNode.events["scrollPhase"]?.valueAction?("unknown")
    phaseNode.events["scrollPhase"]?.valueAction?("tracking")
    phaseNode.events["scrollPhase"]?.valueAction?("tracking")
    phaseNode.events["scrollPhase"]?.valueAction?("decelerating|malformed")
    phaseNode.events["scrollPhase"]?.valueAction?("interacting|0,18,300,800,320,640,0,18,320,640,0,0,0,0")
    #expect(phaseChanges.map { $0.1 } == [.tracking, .decelerating, .interacting])
    let firstPhase = try #require(phaseChanges.first)
    #expect(firstPhase.0 == .idle)
    #expect(firstPhase.2 == 0)
    #expect(phaseChanges[1].2 == 0)
    #expect(phaseChanges[2].2 == 18)

    visibilityNode.events["scrollVisibility"]?.valueAction?("true")
    visibilityNode.events["scrollVisibility"]?.valueAction?("false")
    visibilityNode.events["scrollVisibility"]?.valueAction?("anything-else")
    #expect(visible == [true, false, false])
  }

  @Test
  func gestureCompatibilityHonorsPriorityMasksAndDisabledAncestors() {
    let enabled = StaticHTMLFiberRenderer().render(
      VStack {
        Text("low").simultaneousGesture(TapGesture(), including: .gesture)
        Text("exclusive").highPriorityGesture(DragGesture(), including: .all)
        Text("unmasked").gesture(TapGesture(), including: .none)
      }
    )
    #expect(enabled.contains("data-gesture-priority=\"simultaneous\""))
    #expect(enabled.contains("data-gesture-mask=\"gesture\""))
    #expect(enabled.contains("data-high-priority-gesture=\"true\""))
    #expect(enabled.contains("data-gesture-mask=\"all\""))
    let unmasked = StaticHTMLFiberRenderer().render(
      Text("unmasked").gesture(TapGesture(), including: .none)
    )
    #expect(!unmasked.contains("data-gesture-descriptor"))

    let disabled = StaticHTMLFiberRenderer().render(
      Text("disabled").gesture(TapGesture()).disabled(true)
    )
    #expect(!disabled.contains("data-gesture-descriptor"))
  }

  @Test
  func styleProtocolsProvideDefaultsAndValueTypesExposeSwiftUISpellings() {
    #expect(DefaultFormStyle()._swiftUIWebFormStyle == "automatic")
    #expect(DefaultListStyle()._swiftUIWebListStyle == "automatic")
    #expect(DefaultDatePickerStyle()._swiftUIWebDatePickerStyle == "automatic")
    #expect(DefaultToggleStyle()._swiftUIWebToggleStyle == "automatic")
    #expect(DefaultPickerStyle()._swiftUIWebPickerStyle == "automatic")
    #expect(DefaultTextFieldStyle()._swiftUIWebTextFieldStyle == "automatic")

    let automaticToggle: SwiftUIWebCore.DefaultToggleStyle = .automatic
    let switchToggle: SwitchToggleStyle = .switch
    let buttonToggle: ButtonToggleStyle = .button
    let checkboxToggle: CheckboxToggleStyle = .checkbox
    #expect([
      automaticToggle._swiftUIWebToggleStyle, switchToggle._swiftUIWebToggleStyle,
      buttonToggle._swiftUIWebToggleStyle, checkboxToggle._swiftUIWebToggleStyle
    ] == ["automatic", "switch", "button", "checkbox"])

    #expect(InlinePickerStyle()._swiftUIWebPickerStyle == "inline")
    #expect(MenuPickerStyle()._swiftUIWebPickerStyle == "menu")
    #expect(SegmentedPickerStyle()._swiftUIWebPickerStyle == "segmented")
    #expect(NavigationLinkPickerStyle()._swiftUIWebPickerStyle == "navigation-link")
    #expect(PalettePickerStyle()._swiftUIWebPickerStyle == "palette")
    #expect(PlainTextFieldStyle()._swiftUIWebTextFieldStyle == "plain")
    #expect(RoundedBorderTextFieldStyle()._swiftUIWebTextFieldStyle == "rounded-border")
  }

  @Test
  func textInputAndDisplayModifiersRetainTheirSemanticValues() {
    let html = StaticHTMLFiberRenderer().render(
      VStack(spacing: Float(6)) {
        TextField("Email", text: .constant(""))
          .textContentType(nil)
          .submitLabel(.search)
          .keyboardType(.emailAddress)
          .autocorrectionDisabled(false)
          .dynamicTypeSize(.accessibility2)
          .textFieldStyle(.roundedBorder)
        Picker("Mode", selection: .constant("grid")) {
          Option("Grid", value: "grid")
        }
        .pickerStyle(.segmented)
        Toggle("Enabled", isOn: .constant(true)).toggleStyle(.checkbox)
        Text("Effects")
          .zIndex(Float(2))
          .fontWeight(nil)
          .fontDesign(nil)
          .contentTransition(.identity)
          .scaleEffect(x: 1.2, y: 0.8, anchor: .topLeading)
          .rotation3DEffect(.degrees(20), axis: (x: 0, y: 1, z: 0), perspective: 0)
          .shadow(color: .red, radius: 3, x: 2, y: -1)
          .allowsHitTesting(false)
          .labelsHidden()
          .minimumScaleFactor(0.75)
          .safeAreaPadding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
        Text("Float frame")
          .frame(width: Float(80), height: Float(24))
          .padding(Float(4))
          .offset(x: Float(2), y: Float(3))
          .opacity(Float(0.5))
          .cornerRadius(Float(5))
          .border(.blue, width: 2)
      }
    )

    #expect(html.contains("data-layout-gap=\"6.0\""))
    #expect(html.contains("autocomplete=\"off\""))
    #expect(html.contains("data-submit-label=\"search\""))
    #expect(html.contains("data-keyboard-type=\"emailAddress\""))
    #expect(html.contains("autocorrect=\"on\""))
    #expect(html.contains("data-dynamic-type-size=\"accessibility2\""))
    #expect(html.contains("data-text-field-style=\"rounded-border\""))
    #expect(html.contains("data-picker-style=\"segmented\""))
    #expect(html.contains("data-toggle-style=\"checkbox\""))
    #expect(html.contains("data-content-transition=\"identity\""))
    #expect(html.contains("data-rotation3d-perspective=\"0.0\""))
    #expect(html.contains("data-allows-hit-testing=\"false\""))
    #expect(html.contains("data-labels-hidden=\"true\""))
    #expect(html.contains("data-minimum-scale-factor=\"0.75\""))
    #expect(html.contains("calc(env(safe-area-inset-left, 0px) + 2px)"))
    // The frame is a layer of the padding's element (`_SemanticLayers`), so its size is in the layer, not in the style.
    #expect(html.contains("frame-h=24.0") && html.contains("frame-w=80.0"))
    #expect(html.contains("padding: 4px;"))
    #expect(html.contains("border-radius: 5px;"))
    #expect(html.contains("border: 2px solid"))
  }

  @Test
  func geometryAndTargetVisibilityCallbacksIgnoreMalformedAndDuplicateMeasurements() throws {
    var geometryChanges: [(Int, Int)] = []
    let geometryView = Text("Measured").onGeometryChange(
      for: Int.self,
      of: { Int($0.size.width) },
      action: { geometryChanges.append(($0, $1)) }
    )
    let geometryTree = FiberTree(geometryView)
    let geometryNode = try #require(geometryTree.findNode(withEvent: "geometryChange"))
    geometryTree.dispatch(event: "geometryChange", value: "bad", on: geometryNode)
    geometryTree.dispatch(event: "geometryChange", value: "40,20", on: geometryNode)
    geometryTree.dispatch(event: "geometryChange", value: "40,20", on: geometryNode)
    geometryTree.dispatch(event: "geometryChange", value: "10,20,60,30", on: geometryNode)
    #expect(geometryChanges.map { [$0.0, $0.1] } == [[40, 40], [40, 60]])

    var strings: [[String]] = []
    var unsignedIDs: [[UInt64]] = []
    var booleans: [[Bool]] = []
    var unsupported: [[Double]] = []
    let tree = FiberTree(VStack {
      Text("strings").onScrollTargetVisibilityChange(idType: String.self) { strings.append($0) }
      Text("unsigned").onScrollTargetVisibilityChange(idType: UInt64.self) { unsignedIDs.append($0) }
      Text("booleans").onScrollTargetVisibilityChange(idType: Bool.self) { booleans.append($0) }
      Text("unsupported").onScrollTargetVisibilityChange(idType: Double.self) { unsupported.append($0) }
    })
    let targets = descendants(of: tree.renderNode).filter { $0.events["scrollTargetVisibility"] != nil }
    #expect(targets.count == 4)
    tree.dispatch(event: "scrollTargetVisibility", value: "alpha,beta", on: targets[0])
    tree.dispatch(event: "scrollTargetVisibility", value: "42,invalid", on: targets[1])
    tree.dispatch(event: "scrollTargetVisibility", value: "true,false", on: targets[2])
    tree.dispatch(event: "scrollTargetVisibility", value: "1.5,2", on: targets[3])
    #expect(strings == [["alpha", "beta"]])
    #expect(unsignedIDs == [[42]])
    #expect(booleans == [[true, false]])
    #expect(unsupported == [[]])
  }

  @Test
  func longPressAndScrollTransitionExposeHostNeutralPhases() throws {
    var pressed: [Bool] = []
    var actions = 0
    let view = Text("Hold")
      .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 4, perform: { actions += 1 }) {
        pressed.append($0)
      }
    let tree = FiberTree(view)
    let node = try #require(tree.findNode(withEvent: "pointerdown"))
    #expect(node.attributes["data-long-press-duration"] == "0.2")
    #expect(node.attributes["data-long-press-distance"] == "4")
    tree.dispatch(event: "pointerdown", on: node)
    tree.dispatch(event: "pointerup", on: node)
    #expect(pressed == [true, false])
    #expect(actions == 1)

    let disabled = FiberTree(view.disabled(true))
    let disabledNode = try #require(find(disabled.renderNode) { $0.attributes["data-long-press"] == "true" })
    #expect(disabledNode.events["pointerup"] == nil)

    let transition = StaticHTMLFiberRenderer().render(
      Text("Card").scrollTransition { content, phase in
        phase.isIdentity ? content : content.opacity(0.25)
      }
    )
    #expect(transition.contains("data-scroll-transition=\"true\""))
    #expect(transition.contains("data-scroll-transition-identity=\"\""))
    #expect(transition.contains("data-scroll-transition-leading=\"opacity=0.25\""))
    #expect(transition.contains("data-scroll-transition-trailing=\"opacity=0.25\""))
  }

  private func find(_ node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> _RenderNode? {
    if predicate(node) { return node }
    for child in node.children {
      if let match = find(child, where: predicate) { return match }
    }
    return nil
  }

  private func descendants(of node: _RenderNode) -> [_RenderNode] {
    [node] + node.children.flatMap(descendants)
  }
}
