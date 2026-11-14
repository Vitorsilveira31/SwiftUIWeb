import Testing
import Foundation
@testable import SwiftUIWeb
import SwiftUIWebWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
import SwiftUIWebCharts
import SwiftUIWebMapKit
@_spi(Renderer) import SwiftUIWebFiber

@Observable final class ObservableFixtureModel {
  var name = "Ada"
  var count = 0
}

@Observable final class ObservationIgnoredFixtureModel {
  @ObservationIgnored var ignored = 0
}

@Observable final class NestedObservationChild {
  var value = 0
}

@Observable final class NestedObservationParent {
  var child = NestedObservationChild()
}

@Observable final class CollectionObservationItem {
  let id: Int
  var title: String

  init(id: Int, title: String) {
    self.id = id
    self.title = title
  }
}

@Observable final class CollectionObservationModel {
  var items: [CollectionObservationItem]

  init(items: [CollectionObservationItem]) {
    self.items = items
  }
}

private struct ReusableTestHoverEffect: CustomHoverEffect {
  typealias Body = ContentHoverEffect<_HoverEffectVisual>

  func body(content: EmptyHoverEffect) -> Body {
    ContentHoverEffect { effect, isActive, _ in
      effect.opacity(isActive ? 1 : 0.5)._hoverEffectVisual
    }
  }
}

@Suite(.processGlobalState)
@MainActor
final class PartialBehaviorTests {
  @Test
  func testColorSchemeRuntimeDrivesUnconfiguredEnvironmentDefaults() {
    let previous = ColorSchemeRuntime.current
    defer { ColorSchemeRuntime.install(previous) }

    ColorSchemeRuntime.install(.dark)
    _expectEqual(EnvironmentValues().colorScheme, .dark)
    ColorSchemeRuntime.install(.light)
    _expectEqual(EnvironmentValues().colorScheme, .light)
  }

  @Test
  func testSemanticColorsUseStylesheetDesignTokens() {
    _expectEqual(Color.background.cssValue, "var(--color-swu-background)")
    _expectEqual(Color.surface.cssValue, "var(--color-swu-surface)")
    _expectEqual(Color.cardForeground.cssValue, "var(--color-swu-card-foreground)")

    let html = StaticHTMLFiberRenderer().render(
      Text("Tokenized").background(Color.surface).foregroundStyle(.primary).border(Color.border)
    )
    _expectTrue(html.contains("background-color: var(--color-swu-surface);"))
    _expectTrue(html.contains("color: currentColor"))
    _expectTrue(html.contains("var(--color-swu-border)"))
  }

  @Test
  func testCompositeStateDefaultsAndInputSurviveFiberRefresh() {
    struct FormFixture: View {
      @State var first = "one"
      @State var second = "two"

      var body: some View {
        VStack {
          TextField("First", text: $first)
          TextField("Second", text: $second)
        }
      }
    }

    let fixture = FormFixture()
    let tree = FiberTree(fixture)
    _expectTrue(tree.renderNode.htmlDescription.contains("placeholder=\"First\" type=\"text\" value=\"one\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("placeholder=\"Second\" type=\"text\" value=\"two\""))

    tree.dispatch(event: "input", value: "updated")
    _ = tree.update(fixture)
    _expectTrue(tree.renderNode.htmlDescription.contains("value=\"updated\""))
  }

  @Test
  func testProjectedStateBindingsRemainIndependentThroughSections() {
    struct Fixture: View {
      @State var first = "one"
      @State var second = "two"
      var body: some View {
        Form {
          Section("Fields") {
            TextField("First", text: $first)
            TextField("Second", text: $second)
          }
        }
      }
    }
    let fixture = Fixture()
    let html = FiberTree(fixture).renderNode.htmlDescription
    _expectTrue(html.contains("placeholder=\"First\" type=\"text\" value=\"one\""))
    _expectTrue(html.contains("placeholder=\"Second\" type=\"text\" value=\"two\""))
  }

  @Test
  func testConditionalStateDoesNotAliasWhenBranchFirstAppears() {
    struct Fixture: View {
      @State var showDetails = false
      @State var expanded = true

      var body: some View {
        VStack {
          Toggle("Show details", isOn: $showDetails)
          if showDetails {
            DisclosureGroup("Details", isExpanded: $expanded) {
              Text("Content")
            }
          }
        }
      }
    }

    let fixture = Fixture()
    let tree = FiberTree(fixture)
    fixture.showDetails = true
    _ = tree.update(fixture)
    _expectTrue(tree.renderNode.htmlDescription.contains("open=\"open\""))
  }

  @Test
  func testFocusStateBindingAdoptsTheFiberStoreBeforeProgrammaticFocus() {
    struct Fixture: View {
      @FocusState private var focused: Bool

      var body: some View {
        VStack {
          TextField("Focus target", text: .constant(""))
            .focused($focused)
          Button("Focus") { focused = true }
        }
      }
    }

    let fixture = Fixture()
    let tree = FiberTree(fixture)
    let button = findElements(named: "button", in: tree.renderNode).first
    button?.events["click"]?.action()
    _ = tree.update(fixture)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-focus-request=\"true\""))
  }

  @Test
  func testObservableMacroAndBindableProjectModelProperties() {
    struct Editor: View {
      @Bindable var model: ObservableFixtureModel
      var body: some View {
        TextField("Name", text: $model.name)
      }
    }

    let model = ObservableFixtureModel()
    let tree = FiberTree(Editor(model: model))
    tree.dispatch(event: "input", value: "Grace")
    _expectEqual(model.name, "Grace")

    model.name = "Lin"
    // Observation invalidation is scheduled at the Fiber boundary; an
    // explicit reconciliation is deterministic for a native test host.
    _ = tree.update(Editor(model: model))
    _expectTrue(tree.renderNode.htmlDescription.contains("value=\"Lin\""))
  }

  @Test
  func testObservableMacroCanNotifyAnExternalHostCommit() {
    struct ModelView: View {
      let model: ObservableFixtureModel
      var body: some View { Text(model.name) }
    }
    let model = ObservableFixtureModel()
    let tree = FiberTree(ModelView(model: model))
    var invalidations = 0
    tree.setExternalInvalidationHandler { invalidations += 1 }

    model.name = "Grace"

    // Observation invokes its callback from willSet. The host is notified
    // immediately, while the retained Fiber snapshot is committed on the
    // next render access and therefore observes the new value.
    _expectEqual(invalidations, 1)
    _expectTrue(tree.renderNode.htmlDescription.contains("Grace"))
  }

  @Test
  func testObservationInvalidationTargetsOwningViewBoundary() {
    final class Counters {
      var leftBodies = 0
      var rightBodies = 0
    }
    struct Child: View {
      let model: ObservableFixtureModel
      let side: String
      let counters: Counters
      var body: some View {
        if side == "left" { counters.leftBodies += 1 } else { counters.rightBodies += 1 }
        return Text("\(side):\(model.name)")
      }
    }
    struct Root: View {
      let left: Child
      let right: Child
      var body: some View { VStack { left; right } }
    }

    let counters = Counters()
    let leftModel = ObservableFixtureModel()
    let rightModel = ObservableFixtureModel()
    let tree = FiberTree(Root(
      left: Child(model: leftModel, side: "left", counters: counters),
      right: Child(model: rightModel, side: "right", counters: counters)
    ))
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    leftModel.name = "Grace"

    _expectTrue(tree._hasPendingSubtreeInvalidation)
    _ = tree._drainSubtreeUpdates()
    _expectEqual(counters.leftBodies, 2)
    // Observation callbacks can conservatively include the nearest shared
    // erased boundary when nested access lists overlap. That boundary is the
    // smallest proven safe owner; the update must still avoid a root fallback.
    _expectLessThanOrEqual(counters.rightBodies, 2)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("left:Grace"))
    _expectEqual(tree.metrics.schedulerStructuralFlushes, 0)
    _expectEqual(tree.metrics.schedulerSubtreeFlushes, 1)
  }

  @Test
  func testObservationIgnoredDoesNotInvalidateAView() {
    final class Counters { var bodies = 0 }
    struct ViewUnderTest: View {
      let model: ObservationIgnoredFixtureModel
      let counters: Counters
      var body: some View {
        counters.bodies += 1
        return Text("Ignored: \(model.ignored)")
      }
    }

    let model = ObservationIgnoredFixtureModel()
    let counters = Counters()
    let tree = FiberTree(ViewUnderTest(model: model, counters: counters))
    let initialBodies = counters.bodies

    model.ignored = 1
    _expectEqual(counters.bodies, initialBodies)
    _expectFalse(tree._hasPendingSubtreeInvalidation)
    _expectTrue(tree.renderNode.htmlDescription.contains("Ignored: 0"))
    _expectEqual(counters.bodies, initialBodies)
  }

  @Test
  func testNestedObservableStateTracksChildReplacementAndMutation() {
    final class Counters { var bodies = 0 }
    struct ViewUnderTest: View {
      let model: NestedObservationParent
      let counters: Counters
      var body: some View {
        counters.bodies += 1
        return Text("Child: \(model.child.value)")
      }
    }

    let model = NestedObservationParent()
    let counters = Counters()
    let tree = FiberTree(ViewUnderTest(model: model, counters: counters))
    let initialBodies = counters.bodies

    model.child.value = 4
    _expectTrue(tree.renderNode.htmlDescription.contains("Child: 4"))
    _expectEqual(counters.bodies, initialBodies + 1)

    model.child = NestedObservationChild()
    model.child.value = 9
    _expectTrue(tree.renderNode.htmlDescription.contains("Child: 9"))
    _expectEqual(counters.bodies, initialBodies + 2)
  }

  @Test
  func testTypedEnvironmentObservableStateTracksWithoutReplacingIdentity() {
    final class IdentityProbe { var objectID: ObjectIdentifier? }
    struct EnvironmentView: View {
      @Environment(NestedObservationChild.self) private var model
      let probe: IdentityProbe
      var body: some View {
        probe.objectID = ObjectIdentifier(model)
        return Text("Environment: \(model.value)")
      }
    }

    let model = NestedObservationChild()
    let probe = IdentityProbe()
    let tree = FiberTree(EnvironmentView(probe: probe).environment(model))
    let identity = ObjectIdentifier(model)
    _expectEqual(probe.objectID, identity)
    _expectTrue(tree.renderNode.htmlDescription.contains("Environment: 0"))

    model.value = 7
    _expectTrue(tree.renderNode.htmlDescription.contains("Environment: 7"))
    _expectEqual(probe.objectID, identity)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("Environment: 7"))
  }

  @Test
  func testCollectionObservationInvalidatesOnlyTheChangedRow() {
    final class Counters {
      var listBodies = 0
      var rowBodies: [Int: Int] = [:]
    }
    struct Row: View {
      let item: CollectionObservationItem
      let counters: Counters
      var body: some View {
        counters.rowBodies[item.id, default: 0] += 1
        return Text("Row \(item.id): \(item.title)")
      }
    }
    struct List: View {
      let model: CollectionObservationModel
      let counters: Counters
      var body: some View {
        counters.listBodies += 1
        return ForEach(model.items, id: \.id) { item in
          Row(item: item, counters: counters)
        }
      }
    }

    let first = CollectionObservationItem(id: 1, title: "One")
    let second = CollectionObservationItem(id: 2, title: "Two")
    let model = CollectionObservationModel(items: [first, second])
    let counters = Counters()
    let tree = FiberTree(List(model: model, counters: counters))
    let initialListBodies = counters.listBodies
    let initialFirstBodies = counters.rowBodies[1] ?? 0
    let initialSecondBodies = counters.rowBodies[2] ?? 0

    second.title = "Updated"
    _expectTrue(tree.renderNode.htmlDescription.contains("Row 2: Updated"))
    _expectEqual(counters.listBodies, initialListBodies)
    _expectEqual(counters.rowBodies[1], initialFirstBodies)
    _expectEqual(counters.rowBodies[2], initialSecondBodies + 1)
  }

  @Test
  func testRemovedObservationOwnerCannotInvalidateTheReplacementTree() {
    final class Counters { var bodies = 0 }
    struct Child: View {
      let model: ObservableFixtureModel
      let counters: Counters
      var body: some View {
        counters.bodies += 1
        return Text(model.name)
      }
    }
    struct Root: View {
      let model: ObservableFixtureModel
      let counters: Counters
      let showChild: Bool
      var body: some View {
        if showChild {
          return AnyView(Child(model: model, counters: counters))
        }
        return AnyView(Text("Replacement"))
      }
    }

    let model = ObservableFixtureModel()
    let counters = Counters()
    let tree = FiberTree(Root(model: model, counters: counters, showChild: true))
    _ = tree.update(Root(model: model, counters: counters, showChild: false))
    let bodiesAfterReplacement = counters.bodies

    model.name = "Stale callback"
    _expectTrue(tree.renderNode.htmlDescription.contains("Replacement"))
    _expectEqual(counters.bodies, bodiesAfterReplacement)
    _expectFalse(tree._hasPendingSubtreeInvalidation)
  }

  @Test
  func testButtonStyleControlSizeAndTintMetadata() {
    struct CustomStyle: ButtonStyle {
      func makeBody(configuration: Configuration) -> some View {
        configuration.label
          .padding()
          .background(Color(red: 0, green: 0, blue: 0.5))
          .foregroundStyle(.white)
          .clipShape(Capsule())
      }
    }
    let html = StaticHTMLFiberRenderer().render(
      Button("Save") {}
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.blue)
    )
    _expectTrue(html.contains("data-button-style=\"bordered-prominent\""))
    _expectTrue(html.contains("data-control-size=\"large\""))
    _expectTrue(html.contains("data-tint=\"\(Color.blue.cssValue)\""))

    let custom = StaticHTMLFiberRenderer().render(Button("Custom") {}.buttonStyle(CustomStyle()))
    _expectTrue(custom.contains("Custom"))
    _expectTrue(custom.contains("data-button-style-custom=\"true\""))
    _expectTrue(custom.contains("background-color: rgba(0, 0, 127, 1.0);"))
    _expectTrue(custom.contains("border-radius: 9999px;"))
    _expectTrue(custom.contains("color: white;"))

    struct AppModifier: ViewModifier {
      func body(content: Content) -> some View {
        content.opacity(0.5).padding(4)
      }
    }
    let appModifierHTML = StaticHTMLFiberRenderer().render(Text("Modifier").modifier(AppModifier()))
    _expectTrue(appModifierHTML.contains("Modifier"))
    _expectTrue(appModifierHTML.contains("opacity: 0.5;"))
  }

  @Test
  func testProjectControlOverloadsAndScrollSemantics() {
    let toggle = Toggle(isOn: .constant(true)) {
      VStack(alignment: .leading) {
        Text("Notifications")
        Text("Receive updates").font(.caption)
      }
    }
    let toggleHTML = StaticHTMLFiberRenderer().render(toggle.toggleStyle(.switch))
    _expectTrue(toggleHTML.contains("toggle-switch"))
    _expectTrue(toggleHTML.contains("aria-label=\"Notifications Receive updates\""))

    let progress = StaticHTMLFiberRenderer().render(ProgressView("Loading", value: 0.5, total: 1))
    _expectTrue(progress.contains("<progress"))
    _expectTrue(progress.contains("aria-label=\"Loading\""))
    _expectTrue(progress.contains("value=\"0.5\""))

    var visibility: [Bool] = []
    let visibilityView = ScrollView { Text("Content") }
      .defaultScrollAnchor(.bottom)
      .scrollEdgeEffectHidden(true)
      .onScrollVisibilityChange(threshold: 0.01) { visibility.append($0) }
    let visibilityTree = FiberTree(visibilityView)
    visibilityTree.dispatch(event: "scrollVisibility", value: "true")
    visibilityTree.dispatch(event: "scrollVisibility", value: "false")
    _expectEqual(visibility, [true, false])

    let scroll = StaticHTMLFiberRenderer().render(visibilityView)
    _expectTrue(scroll.contains("data-default-scroll-anchor=\"0.5,1\""))
    _expectTrue(scroll.contains("data-scroll-edge-effect-hidden=\"15\""))
    _expectTrue(scroll.contains("data-scroll-visibility-threshold=\"0.01\""))

    let insetScroll = StaticHTMLFiberRenderer().render(
      ScrollView { Text("Insets") }
        .contentMargins(.all, EdgeInsets(top: 0, leading: 12, bottom: 24, trailing: 12), for: .scrollContent)
    )
    _expectTrue(insetScroll.contains("padding-left: 12px;"))
    _expectTrue(insetScroll.contains("padding-bottom: 24px;"))
  }

  @Test
  func testViewThatFitsMarksCandidatesAndScrollReaderUsesStableIDs() {
    let fitHTML = StaticHTMLFiberRenderer().render(ViewThatFits {
      Text("Compact")
      Text("Regular")
    })
    _expectTrue(fitHTML.contains("data-view-that-fits=\"both\""))
    _expectTrue(fitHTML.contains("data-fit-index=\"0\""))
    _expectTrue(fitHTML.contains("data-fit-index=\"1\""))

    let position = Binding<Int?>(get: { 2 }, set: { _ in })
    let positionHTML = StaticHTMLFiberRenderer().render(
      ScrollView { ForEach([1, 2, 3], id: \.self) { Text("\($0)").id($0) } }
        .scrollPosition(id: position, anchor: .center)
    )
    _expectTrue(positionHTML.contains("data-scroll-position=\"true\""))
    _expectTrue(positionHTML.contains("data-scroll-position-id=\"2\""))
    _expectTrue(positionHTML.contains("data-scroll-position-anchor=\"0.5,0.5\""))

    let view = ScrollViewReader { proxy in
      VStack {
        Button("Jump") { proxy.scrollTo(42, anchor: .center) }
        Text("Target").id(42)
      }
    }
    let tree = FiberTree(view)
    tree.dispatch(event: "click")
    _expectEqual(ScrollViewRuntime.lastRequest?.0, "42")
    _expectEqual(ScrollViewRuntime.lastRequest?.1, .center)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-view-id=\"42\""))
  }

  @Test
  func testPresentationDetentsRemainSwiftUIShapedAndCarryInitialSizingMetadata() {
    struct DetentFixture: View {
      @State private var presented = true

      var body: some View {
        Text("Root").sheet(isPresented: $presented) {
          Text("Details")
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
      }
    }

    let html = StaticHTMLFiberRenderer().render(DetentFixture())
    _expectTrue(html.contains("data-presentation-detents=\"large,medium\""), html)
    _expectTrue(html.contains("data-presentation-drag-indicator=\"visible\""), html)
  }

  @Test
  func testTextAndSecureFieldPromptInitializersPreserveSwiftUIShape() {
    let text = TextField("", text: .constant(""), prompt: Text("Search"))
    let secure = SecureField(text: .constant(""), prompt: Text("Password")) { Text("Password") }

    let textHTML = StaticHTMLFiberRenderer().render(text)
    let secureHTML = StaticHTMLFiberRenderer().render(secure)
    _expectTrue(textHTML.contains("placeholder=\"Search\""), textHTML)
    _expectTrue(textHTML.contains("aria-label=\"Search\""), textHTML)
    _expectTrue(secureHTML.contains("type=\"password\""), secureHTML)
    _expectTrue(secureHTML.contains("placeholder=\"Password\""), secureHTML)
    _expectTrue(secureHTML.contains("aria-label=\"Password\""), secureHTML)
  }

  @Test
  func testRefreshRedactionSafeAreaAndAccessibilityMetadata() {
    struct RefreshAware: View {
      @Environment(\.refresh) private var refresh
      var body: some View { Text(refresh == nil ? "not-refreshable" : "refreshable") }
    }
    let refreshHTML = StaticHTMLFiberRenderer().render(
      RefreshAware().refreshable { }
    )
    _expectTrue(refreshHTML.contains("refreshable"))

    let html = StaticHTMLFiberRenderer().render(
      Text("Loading")
        .redacted(reason: .placeholder)
        .safeAreaInset(edge: .bottom, spacing: 4) { Text("Toolbar") }
        .accessibilityValue("Loading value")
        .accessibilityHint("Please wait")
        .accessibilityAddTraits([.updatesFrequently, .isHeader])
        .accessibilityHidden(false)
    )
    _expectTrue(html.contains("redacted"))
    _expectTrue(html.contains("data-safe-area-edge=\"bottom\""))
    _expectTrue(!html.contains("aria-valuetext="))
    _expectTrue(html.contains("aria-description=\"Loading value. Please wait\""))
    _expectTrue(html.contains("aria-live=\"polite\""))
    _expectTrue(html.contains("role=\"heading\""))
  }

  @Test
  func testRefreshableCarriesAFiberOwnedRefreshEvent() {
    let tree = FiberTree(
      ScrollView { Text("Pull to refresh") }
        .refreshable { }
    )
    let node = tree.findNode(withEvent: "refresh")
    _expectNotNil(node)
    _expectEqual(node?.attributes["data-refreshable"], "true")
  }

  @Test
  func testModernOnChangeAndSubmitOverloads() {
    var noArgumentCalls = 0
    var pairs: [(Int, Int)] = []
    let first = Text("Value")
      .onChange(of: 1, initial: true) { noArgumentCalls += 1 }
      .onChange(of: 1, initial: true) { oldValue, newValue in pairs.append((oldValue, newValue)) }
    let tree = FiberTree(first)
    _expectEqual(noArgumentCalls, 1)
    _expectEqual(pairs.count, 1)
    _ = tree.update(Text("Value").onChange(of: 2) { oldValue, newValue in pairs.append((oldValue, newValue)) })
    _expectEqual(pairs.last?.0, 1)
    _expectEqual(pairs.last?.1, 2)

    let submit = TextField("Name", text: .constant("")).onSubmit(of: [.text, .form]) { noArgumentCalls += 1 }
    let submitTree = FiberTree(submit)
    submitTree.dispatch(event: "submit")
    _expectEqual(noArgumentCalls, 2)
    _expectTrue(submitTree.renderNode.htmlDescription.contains("data-submit-triggers=\"9\""))
  }

  @Test
  func testProjectCompatibilityPrimitivesRender() {
    _ = Image("FixtureAsset", bundle: Bundle.main)
    let text = StaticHTMLFiberRenderer().render(
      Text(Date(timeIntervalSince1970: 0), style: .date)
    )
    _expectTrue(text.contains("data-text-date-style=\"date\""))

    let field = StaticHTMLFiberRenderer().render(
      TextField("Notes", text: .constant("hello"), axis: .vertical)
    )
    _expectTrue(field.contains("<textarea"))
    _expectTrue(field.contains("data-axis=\"vertical\""))
    _expectTrue(field.contains("hello"))

    let share = StaticHTMLFiberRenderer().render(
      ShareLink(item: "https://example.com", subject: Text("Subject"), message: Text("Message")) {
        Label("Share", systemImage: "square.and.arrow.up")
      }
    )
    _expectTrue(share.contains("share-link"))
    _expectTrue(share.contains("data-share-item=\"https://example.com\""))
    _expectTrue(share.contains("data-share-subject=\"Subject\""))

    let asyncImage = StaticHTMLFiberRenderer().render(
      AsyncImage(url: URL(string: "https://example.com/poster.jpg")) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        ProgressView()
      }
    )
    _expectTrue(asyncImage.contains("async-image"))

    let layout = StaticHTMLFiberRenderer().render(Grid(horizontalSpacing: 8, verticalSpacing: 4) {
      GridRow { Text("A"); Text("B") }
      GridRow { Text("C"); Text("D") }
    })
    _expectTrue(layout.contains("regular-grid"))
    _expectTrue(layout.contains("grid-row"))

    let timeline = StaticHTMLFiberRenderer().render(
      TimelineView(.everyMinute) { context in
        Text(context.cadence == .minutes ? "minute" : "live")
      }
    )
    _expectTrue(timeline.contains("minute"))

    let animatedTimeline = StaticHTMLFiberRenderer().render(
      TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
        Text(context.date.description)
      }
    )
    _expectFalse(animatedTimeline.isEmpty)
  }

  @Test
  func testImagePipelineKeepsRemoteLoadingHintsInSemanticMarkup() {
    let remote = StaticHTMLFiberRenderer().render(
      Image("https://cdn.example.test/avatar.webp", alt: "Avatar")
    )
    _expectTrue(remote.contains("class=\"picture-view\""))
    _expectTrue(remote.contains("loading=\"lazy\""))
    _expectTrue(remote.contains("decoding=\"async\""))
    _expectTrue(remote.contains("alt=\"Avatar\""))

    let local = StaticHTMLFiberRenderer().render(Image("avatar.png"))
    _expectTrue(local.contains("class=\"picture-view\""))
    _expectTrue(local.contains("loading=\"lazy\""))
    _expectTrue(local.contains("decoding=\"async\""))
  }

  @Test
  func testAsyncImageLoaderCarriesBrowserPipelineMetadata() {
    let html = StaticHTMLFiberRenderer().render(
      AsyncImage(url: URL(string: "https://cdn.example.test/poster.avif"), scale: 2) { phase in
        if phase.image != nil {
          Text("loaded")
        } else {
          Text("loading")
        }
      }
    )
    _expectTrue(html.contains("async-image"))
    _expectTrue(html.contains("async-image-loader"))
    _expectTrue(html.contains("decoding=\"async\""))
    _expectTrue(html.contains("data-scale=\"2\""))
  }

  @Test
  func testOpenURLKeepsSwiftUIEnvironmentShape() {
    final class OpenedURLs: @unchecked Sendable {
      var values: [String] = []
    }
    let opened = OpenedURLs()
    var environment = EnvironmentValues()
    environment.openURL = OpenURLAction { url in
      opened.values.append(url.absoluteString)
      return .handled
    }
    // SwiftUI's `callAsFunction(_:)` returns Void; the handler's result is discarded.
    environment.openURL(URL(string: "https://example.com")!)
    _expectEqual(opened.values, ["https://example.com"])
  }

  @Test
  func testTypedEnvironmentObjectsLocaleScenePhaseAndPreferences() {
    final class SessionModel {
      let title: String
      init(title: String) { self.title = title }
    }

    struct EnvironmentView: View {
      @Environment(SessionModel.self) var model
      @Environment(\.locale) var locale
      @Environment(\.scenePhase) var phase
      var body: some View { Text("\(model.title)-\(locale.identifier)-\(phase)") }
    }

    var environment = EnvironmentValues()
    environment.locale = Locale(identifier: "pt_BR")
    environment.scenePhase = .background
    let html = StaticHTMLFiberRenderer().render(EnvironmentView().environment(SessionModel(title: "Ready")), environment: environment)
    _expectTrue(html.contains("Ready-pt_BR-background"))

    struct AccessibilityEnvironmentView: View {
      @Environment(\.accessibilityReduceMotion) var reduceMotion
      @Environment(\.accessibilityReduceTransparency) var reduceTransparency
      @Environment(\.dynamicTypeSize) var typeSize
      @Environment(\.isFocused) var focused
      var body: some View {
        Text("\(reduceMotion)-\(reduceTransparency)-\(typeSize.isAccessibilitySize)-\(focused)")
      }
    }
    var accessibilityEnvironment = EnvironmentValues()
    accessibilityEnvironment.accessibilityReduceMotion = true
    accessibilityEnvironment.accessibilityReduceTransparency = true
    accessibilityEnvironment.dynamicTypeSize = .accessibility3
    accessibilityEnvironment.isFocused = true
    let accessibilityHTML = StaticHTMLFiberRenderer().render(AccessibilityEnvironmentView(), environment: accessibilityEnvironment)
    _expectTrue(accessibilityHTML.contains("true-true-true-true"))

    struct CountPreference: PreferenceKey {
      static let defaultValue = 0
      static func reduce(value: inout Int, nextValue: () -> Int) { value = nextValue() }
    }
    var values: [Int] = []
    let first = Text("Preference")
      .preference(key: CountPreference.self, value: 1)
      .onPreferenceChange(CountPreference.self) { values.append($0) }
    let tree = FiberTree(first)
    _expectEqual(values, [1])
    _ = tree.update(Text("Preference").preference(key: CountPreference.self, value: 1).onPreferenceChange(CountPreference.self) { values.append($0) })
    _expectEqual(values, [1])
    _ = tree.update(Text("Preference").preference(key: CountPreference.self, value: 2).onPreferenceChange(CountPreference.self) { values.append($0) })
    _expectEqual(values, [1, 2])
  }

  @Test
  func testAngularGradientAndURLCallbackRemainBackendNeutral() {
    let gradient = AngularGradient(colors: [.blue, .purple, .red], center: .center, angle: .degrees(15))
    let html = StaticHTMLFiberRenderer().render(Rectangle().fill(gradient))
    _expectTrue(html.contains("conic-gradient"))
    _expectTrue(html.contains("from ") && html.contains("deg at"))

    let contextualShape = StaticHTMLFiberRenderer().render(Text("Card").background(Color.blue, in: .rect(cornerRadius: 8)))
    _expectTrue(contextualShape.contains("data-background-shape=\"rounded-rectangle-8\""))

    var received: String?
    let tree = FiberTree(Text("Open").onOpenURL { received = $0.absoluteString })
    tree.dispatch(event: "openURL", value: "https://example.com/path")
    _expectEqual(received, "https://example.com/path")
  }

  @Test
  func testShapesAndGradientsRemainSwiftUIShaped() {
    let html = StaticHTMLFiberRenderer().render(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: 120, height: 40)
        .clipShape(Capsule())
        .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
    )
    _expectTrue(html.contains("data-shape=\"rounded-rectangle-12\""))
    _expectTrue(html.contains("data-shape-style=\"fill\""))
    _expectTrue(html.contains("linear-gradient"))
    _expectTrue(html.contains("data-clip-shape=\"capsule\""))
    _expectTrue(html.contains("data-background-shape=\"rounded-rectangle-14\""))
  }

  @Test
  func testCustomShapePathUsesSwiftUIMutationSyntax() {
    struct ConnectorShape: Shape {
      func path(in rect: CGRect) -> Path {
        Path { path in
          path.move(to: CGPoint(x: rect.origin.x, y: rect.origin.y))
          path.addLine(to: CGPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y + rect.size.height))
          path.closeSubpath()
        }
      }
    }

    let html = StaticHTMLFiberRenderer().render(ConnectorShape().stroke(Color.blue, lineWidth: 2))
    _expectTrue(html.contains("data-shape=\"shape\""))
    _expectTrue(html.contains("data-shape-style=\"stroke\""))
  }

  @Test
  func testProjectVisualEffectModifiersRemainSemanticAndStylesheetReady() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Preview")
        .blur(radius: 4)
        .blendMode(.overlay)
        .compositingGroup()
        .drawingGroup()
        .mask { Circle() }
    )
    _expectTrue(html.contains("data-blend-mode=\"overlay\""))
    _expectTrue(html.contains("data-compositing-group=\"true\""))
    _expectTrue(html.contains("data-drawing-group=\"true\""))
    _expectTrue(html.contains("data-mask=\"true\""))
  }

  @Test
  func testBrowserNeutralCanvasMapWebViewAndChartPrimitives() {
    let html = StaticHTMLFiberRenderer().render(VStack {
      Canvas { context, _ in context.fill(Path(), with: .blue) }
      Map()
      WebContentView(url: "https://example.com")
      Chart { PointMark(x: .value("X", 1), y: .value("Series", 1)) }
    })
    _expectTrue(html.contains("draw-canvas"))
    _expectTrue(html.contains("mapkit-view"))
    _expectTrue(html.contains("web-view"))
    _expectTrue(html.contains("data-chart"))
  }

  @Test
  func testFlexibleWidthPropagatesThroughRowsControlsAndFrames() {
    let html = StaticHTMLFiberRenderer().render(VStack {
      HStack {
        Text("Airplane Mode")
        Spacer(minLength: 8)
        Toggle("", isOn: .constant(false))
      }
      Button(action: {}) {
        HStack {
          Text("Wi-Fi")
          Spacer(minLength: 0)
          Text("chevron")
        }
      }
      NavigationLink(destination: Text("Details")) {
        HStack {
          Text("Details")
          Spacer(minLength: 0)
        }
      }
      HStack {
        Spacer(minLength: 0).frame(width: 20)
        Text("Fixed spacer")
      }
      Button(action: {}) {
        VStack {
          Text("Vertical content")
          Spacer(minLength: 0)
        }
      }
      Text("Flexible frame").frame(maxWidth: .infinity)
    })

    let flexibleNodes = html.components(separatedBy: "data-flexible-width=\"true\"").count - 1
    _expectEqual(flexibleNodes, 6)
    _expectTrue(html.contains("data-frame-max-w=\"inf\""))
  }

  @Test
  func testBrowserControlsExposeCompactStylesheetHooks() {
    let binding = Binding<String>(get: { "Ada" }, set: { _ in })
    let toggleBinding = Binding<Bool>(get: { true }, set: { _ in })
    let html = StaticHTMLFiberRenderer().render(VStack {
      Button("Save") {}
      NavigationLink("Profile", destination: Text("Profile"))
      TextField("Name", text: binding)
      Toggle("Notifications", isOn: toggleBinding)
      ScrollView { Text("Content") }
      Divider()
      Form { Section("Account") { Text("Details") } }
      DisclosureGroup("More") { Text("Details") }
      Image("avatar.png")
    })

    _expectTrue(html.contains("push-button"))
    _expectTrue(html.contains("navigation-link"))
    _expectTrue(html.contains("field-input"))
    _expectTrue(html.contains("toggle-switch"))
    _expectTrue(html.contains("role=\"switch\""))
    _expectTrue(html.contains("scroll-view"))
    _expectTrue(html.contains("section-block"))
    _expectTrue(html.contains("disclosure-group"))
    _expectTrue(html.contains("picture-view"))
  }

  @Test
  func testFlexibleFramesAndSpacersDescribeViewportLayout() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Text("Header")
        Spacer(minLength: 12)
        Text("Footer")
      }
      .frame(maxWidth: Double.infinity, maxHeight: Double.infinity, alignment: .bottomTrailing)
    )

    // Infinity is a SwiftUI request to accept the parent's full proposal, not
    // an invalid CSS `infpx` value. Spacer's minimum belongs to the stack's
    // main axis and is carried as host-neutral metadata for CSS orientation.
    _expectTrue(html.contains("max-height: 100%;"))
    _expectTrue(html.contains("max-width: 100%;"))
    _expectTrue(html.contains("height: 100%;"))
    _expectTrue(html.contains("width: 100%;"))
    _expectTrue(html.contains("data-frame-alignment=\"end\""))
    _expectTrue(html.contains("--spacer-min-length: 12px;"))

    let grid = StaticHTMLFiberRenderer().render(
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))]) {
        Text("A")
        Text("B")
      }
      .frame(maxWidth: Double.infinity)
    )
    // Framing a grid must preserve its native CSS grid display. A generic
    // frame alignment is a layout boundary, not permission to turn the grid
    // into a flex row.
    _expectTrue(grid.contains("grid-layout"))
    _expectFalse(grid.contains("display: flex"))
  }

  @Test
  func testNestedFramesPreserveInnerConstraintAndOuterProposal() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Column")
        .frame(maxWidth: 620, alignment: .leading)
        .padding()
        .frame(maxWidth: Double.infinity, alignment: .center)
    )

    // The outer frame is a real internal layout boundary, so it cannot
    // overwrite the constrained inner column as an in-place CSS property: the chain is a frame around a padding around a
    // frame, the two frames layers of one element (`_SemanticLayers`), each with its own size and alignment.
    // An empty frame is also hit-transparent (see HitTestingTests).
    _expectTrue(html.contains("class=\"frame-box padding passthrough\""))
    _expectTrue(html.contains("data-frame-max-w=\"inf\""))
    _expectTrue(html.contains("frame-max-w=620.0"))
    _expectTrue(html.contains("max-width: 100%;"))
    _expectTrue(html.contains("data-frame-alignment=\"center\""))
  }

  @Test
  func testSystemImageUsesAccessibleLocalSymbolPrimitive() {
    let html = StaticHTMLFiberRenderer().render(Image(systemName: "sparkles"))
    _expectTrue(html.contains("class=\"symbol-icon\""))
    _expectTrue(html.contains("data-symbol=\"sparkles\""))
    _expectTrue(html.contains("aria-label=\"sparkles\""))
    _expectTrue(html.contains("✦"))
    _expectFalse(html.contains("symbol:sparkles"))
  }

  @Test
  func testCommonSFSymbolVariantsRemainSemanticForBrowserUpgrade() {
    for symbol in ["gearshape", "gearshape.fill", "chevron.left", "trash", "person.fill"] {
      let html = StaticHTMLFiberRenderer().render(Image(systemName: symbol))
      // The browser adapter uses this value to choose Lucide; keeping the SF
      // name in the DOM also makes unknown symbols and non-browser hosts safe.
      _expectTrue(html.contains("data-symbol=\"\(symbol)\""), symbol)
      _expectTrue(html.contains("role=\"img\""), symbol)
      _expectTrue(html.contains("aria-label=\"\(symbol)\""), symbol)
    }
  }

  @Test
  func testOnChangeOnlyRunsAfterAnEquatableValueChanges() {
    var changes: [Int] = []
    let first = Text("Value").onChange(of: 1) { changes.append($0) }
    let tree = FiberTree(first)
    _expectTrue(changes.isEmpty)
    _ = tree.update(Text("Value").onChange(of: 1) { changes.append($0) })
    _expectTrue(changes.isEmpty)
    _ = tree.update(Text("Value").onChange(of: 2) { changes.append($0) })
    _expectEqual(changes, [2])
  }

  @Test
  func testOnChangeEffectRunsAfterTheWholePassHasRendered() {
    final class Log: @unchecked Sendable { var events: [String] = [] }
    struct Sibling: View {
      let log: Log
      var body: some View { let _ = log.events.append("sibling"); return Text("Sibling") }
    }
    let log = Log()
    func screen(_ value: Int) -> some View {
      VStack {
        Text("Value").onChange(of: value) { new in log.events.append("effect \(new)") }
        Sibling(log: log)
      }
    }
    let tree = FiberTree(screen(1))
    log.events.removeAll()
    _ = tree.update(screen(2))
    _expectEqual(log.events, ["sibling", "effect 2"])
  }

  @Test
  func testTaggedTabViewSelectsContentAndBuildsAccessibleTabList() {
    var selected = 1
    let binding = Binding<Int>(get: { selected }, set: { selected = $0 })
    let view = TabView(selection: binding) {
      Text("Home")
        .tabItem { Text("Home") }
        .tag(0)
      Text("Settings")
        .tabItem { Text("Settings") }
        .tag(1)
    }
    let tree = FiberTree(view)
    let initial = tree.renderNode.htmlDescription
    _expectTrue(initial.contains("Settings"))
    _expectTrue(initial.contains("role=\"tablist\""))
    _expectTrue(initial.contains("data-tab-label=\"Settings\""))
    tree.dispatch(event: "click", on: tree.findNode(withEvent: "click"))
    _expectEqual(selected, 0)
    _ = tree.update(view)
    _expectTrue(tree.renderNode.htmlDescription.contains("Home"))

    enum ProjectTab: String, Hashable { case home, settings }
    var projectTab = ProjectTab.settings
    let projectView = TabView(selection: Binding(get: { projectTab }, set: { projectTab = $0 })) {
      Text("Home").tag(ProjectTab.home)
      Text("Settings").tag(ProjectTab.settings)
    }
    let projectTree = FiberTree(projectView)
    projectTree.dispatch(event: "click", on: projectTree.findNode(withEvent: "click"))
    _expectEqual(projectTab, .home)

    let modernView = TabView(selection: Binding(get: { projectTab }, set: { projectTab = $0 })) {
      Tab("Home", systemImage: "house", value: ProjectTab.home) { Text("Home screen") }
      Tab(value: ProjectTab.settings) { Text("Settings screen") } label: { Label("Settings", systemImage: "gearshape") }
    }
    let modernHTML = StaticHTMLFiberRenderer().render(modernView)
    _expectTrue(modernHTML.contains("data-tab-modern=\"true\""))
    _expectTrue(modernHTML.contains("Settings"), modernHTML)
  }

  @Test
  func testModernTabsRetainAllPanelsAndSupportSectionsBadgesRolesAndCustomization() {
    enum TabID: String, Hashable { case home, inbox, search }
    var selected = TabID.inbox
    var customization = TabViewCustomization(hiddenTabs: ["home"], order: ["search", "inbox", "home"])
    let binding = Binding(get: { selected }, set: { selected = $0 })
    let customizationBinding = Binding(get: { customization }, set: { customization = $0 })
    let view = TabView(selection: binding) {
      Tab("Home", systemImage: "house", value: TabID.home) { Text("Home state") }
        .customizationID("home")
      TabSection("Workspace") {
        Tab("Inbox", systemImage: "circle", value: TabID.inbox) { Text("Inbox state") }
          .badge(7)
        Tab(value: TabID.search, role: .search) { Text("Search state") }
          .customizationID("search")
          .disabled(true)
      }
    }
    .tabViewCustomization(customizationBinding)

    let tree = FiberTree(view)
    let initial = tree.renderNode.htmlDescription
    _expectTrue(initial.contains("data-tab-section-title=\"Workspace\""), initial)
    _expectTrue(initial.contains("data-badge=\"7\""), initial)
    _expectTrue(initial.contains("data-tab-role=\"search\""), initial)
    _expectTrue(initial.contains("aria-hidden=\"true\""), "Unselected tab panels stay mounted")
    _expectTrue(initial.contains("data-tab-customization=\"true\""), initial)
    _expectTrue(initial.contains("data-tab-value=\"home\""), "Hidden tabs retain their content identity")

    // The disabled search tab must remain visible as a retained panel but
    // cannot be selected through the tab bar.
    let firstClick = tree.findNode(withEvent: "click")
    tree.dispatch(event: "click", on: firstClick)
    _expectEqual(selected, .inbox, "A disabled search tab must not change selection")
  }

  @Test
  func testSidebarAdaptableTabsUseTheSwiftUI18Declaration() {
    let view = TabView {
      Tab("Home", systemImage: "house") {
        Text("Home content")
      }
      TabSection("Library") {
        Tab("Courses", systemImage: "play.rectangle") {
          Text("Courses content")
        }
        Tab("Downloads", systemImage: "arrow.down.circle") {
          Text("Downloads content")
        }
      }
    }
    .tabViewStyle(.sidebarAdaptable)

    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("data-tab-style=\"sidebar-adaptable\""), html)
    _expectTrue(html.contains("data-tab-adaptive=\"sidebar-bottom\""), html)
    _expectTrue(html.contains("data-tab-breakpoints=\"767,1199\""), html)
    _expectTrue(html.contains("data-tab-section-title=\"Library\""), html)
    _expectTrue(html.contains("data-tab-system-image=\"house\""), html)
    _expectTrue(html.contains("data-tab-system-image=\"arrow.down.circle\""), html)
    _expectTrue(html.contains("aria-label=\"Downloads\""), html)
  }

  @Test
  func testTabViewDynamicReorderingUsesStableTabKeys() {
    enum Item: String, Hashable { case one, two, three }
    var selected = Item.two
    var items: [Item] = [.one, .two, .three]
    func makeView() -> some View {
      TabView(selection: Binding(get: { selected }, set: { selected = $0 })) {
        ForEach(items, id: \.self) { item in
          Tab(item.rawValue, systemImage: "circle", value: item) { Text("panel-\(item.rawValue)") }
        }
      }
    }

    let first = makeView()
    let tree = FiberTree(first)
    let before = tree.renderNode.htmlDescription
    _expectTrue(before.contains("panel-two"), before)
    items = [.three, .two, .one]
    _ = tree.update(makeView())
    let after = tree.renderNode.htmlDescription
    _expectTrue(after.contains("data-tab-value=\"three\""), after)
    _expectTrue(after.contains("data-selected-tab=\"two\""), after)
    _expectTrue(after.contains("panel-two"), "The selected panel survives a dynamic reorder")
  }

  @Test
  func testTabSelectionUsesOptionalHistoryAdapterWithoutChangingPublicAPI() {
    final class Recorder: _TabHistoryAdapter {
      var selections: [(String, String)] = []
      var observer: ((String) -> Void)?
      func _updateTab(namespace: String, tag: String) { selections.append((namespace, tag)) }
      func _observeTab(namespace: String, callback: @escaping (String) -> Void) { observer = callback }
      func apply(_ operation: NavigationHistoryOperation) {}
    }

    var selected = 1
    let view = TabView(selection: Binding(get: { selected }, set: { selected = $0 })) {
      Text("One").tabItem { Text("One") }.tag(0)
      Text("Two").tabItem { Text("Two") }.tag(1)
    }
    let recorder = Recorder()
    var environment = EnvironmentValues()
    environment.navigationHistory = recorder
    let tree = FiberTree(view, environment: environment)
    tree.dispatch(event: "click", on: tree.findNode(withEvent: "click"))
    _expectEqual(selected, 0)
    _expectEqual(recorder.selections.last?.1, "0")
    selected = 1
    recorder.observer?("0")
    _expectEqual(selected, 0, "Browser-originated history restores the typed selection")
  }

  @Test
  func testInactiveTabsRetainIndependentNavigationStacks() {
    var selected = 1
    let view = TabView(selection: Binding(get: { selected }, set: { selected = $0 })) {
      NavigationStack { Text("First navigation") }
        .tabItem { Text("First") }
        .tag(0)
      NavigationStack { Text("Second navigation") }
        .tabItem { Text("Second") }
        .tag(1)
    }
    let tree = FiberTree(view)
    _expectEqual(tree.renderNode.htmlDescription.components(separatedBy: "navigation-stack").count - 1, 2)
    tree.dispatch(event: "click", on: tree.findNode(withEvent: "click"))
    _ = tree.update(view)
    let switched = tree.renderNode.htmlDescription
    _expectTrue(switched.contains("First navigation"), switched)
    _expectTrue(switched.contains("Second navigation"), switched)
  }

  @Test
  func testGeometryReaderAcceptsHostMeasurementAndRerendersContent() {
    let view = GeometryReader { proxy in
      Text("\(Int(proxy.size.width))×\(Int(proxy.size.height))")
    }
    let tree = FiberTree(view)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-geometry-reader=\"true\""))
    guard let geometryNode = tree.findNode(withEvent: "geometry") else {
      return _fail("GeometryReader should expose its host measurement event")
    }
    tree.dispatch(event: "geometry", value: "320.5,180.75", on: geometryNode)
    _ = tree.update(view)
    _expectTrue(tree.renderNode.htmlDescription.contains("320×180"))

    let named = GeometryReader { proxy in
      let y = proxy.frame(in: .named("scroll")).origin.y
      Text("\(Int(y))")
    }.coordinateSpace(name: "scroll")
    let namedTree = FiberTree(named)
    _expectTrue(namedTree.renderNode.htmlDescription.contains("data-coordinate-space=\"scroll\""))
    guard let namedGeometry = namedTree.findNode(withEvent: "geometry") else {
      return _fail("Named GeometryReader should expose a host measurement event")
    }
    // The reader is itself the named space's view: its origin in that space
    // is zero wherever the window places it.
    namedTree.dispatch(event: "geometry", value: "12.25,48.5,320.75,180.25\u{1E}n\u{1F}scroll\u{1F}12.25,48.5,320.75,180.25", on: namedGeometry)
    _ = namedTree.update(named)
    _expectTrue(namedTree.renderNode.htmlDescription.contains(">0</div>"), namedTree.renderNode.htmlDescription)
  }

  @Test
  func testOnGeometryChangeReceivesMeasuredValuesThroughFiber() {
    var widths: [Double] = []
    let view = Text("Measured")
      .onGeometryChange(for: Double.self, of: { $0.size.width }) { width in
        widths.append(width)
      }
    let tree = FiberTree(view)
    guard let geometryNode = tree.findNode(withEvent: "geometryChange") else {
      return _fail("onGeometryChange should expose a host measurement event")
    }

    tree.dispatch(event: "geometryChange", value: "100,40", on: geometryNode)
    tree.dispatch(event: "geometryChange", value: "100,40", on: geometryNode)
    tree.dispatch(event: "geometryChange", value: "240,40", on: geometryNode)
    _expectEqual(widths, [100, 240])

    var pairs: [(Double, Double)] = []
    let pairView = Text("Pair")
      .onGeometryChange(for: Double.self, of: { $0.size.width }) { old, new in
        pairs.append((old, new))
      }
    let pairTree = FiberTree(pairView)
    guard let pairNode = pairTree.findNode(withEvent: "geometryChange") else {
      return _fail("pair onGeometryChange should expose a host measurement event")
    }
    pairTree.dispatch(event: "geometryChange", value: "80,20", on: pairNode)
    pairTree.dispatch(event: "geometryChange", value: "160,20", on: pairNode)
    _expectEqual(pairs.map { $0.0 }, [80, 80])
    _expectEqual(pairs.map { $0.1 }, [80, 160])
  }

  @Test
  func testPickerUpdatesSelectionAndMarksSelectedOption() {
    var selection = "swift"
    let binding = Binding<String>(get: { selection }, set: { selection = $0 })
    let picker = Picker("Language", selection: binding) {
      Option("Swift", value: "swift")
      Option("Web", value: "web")
    }

    let tree = FiberTree(picker)
    _expectTrue(tree.renderNode.htmlDescription.contains("value=\"swift\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("selected=\"selected\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("picker-label"))
    _expectTrue(tree.renderNode.htmlDescription.contains("aria-label=\"Language\""))
    tree.dispatch(event: "change", value: "web")
    _expectEqual(selection, "web")
    _ = tree.update(picker)
    _expectTrue(tree.renderNode.htmlDescription.contains("value=\"web\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("selected=\"selected\""))
  }

  @Test
  func testPickerRendersForEachTextTagsAndRestoresTypedSelection() {
    enum WorkflowID: String, Hashable { case story, animation }
    var selection = WorkflowID.story
    let picker = Picker("Workflow", selection: Binding(get: { selection }, set: { selection = $0 })) {
      ForEach([WorkflowID.story, .animation], id: \.self) { value in
        Text(value.rawValue).tag(value)
      }
    }
    let tree = FiberTree(picker)
    func optionValue(_ node: _RenderNode, label: String) -> String? {
      if case .element(let tag) = node.kind, tag == "option",
         node.children.contains(where: { $0.text == label }) {
        return node.attributes["value"]
      }
      for child in node.children {
        if let value = optionValue(child, label: label) { return value }
      }
      return nil
    }

    let html = tree.renderNode.htmlDescription
    _expectTrue(html.contains("<option"))
    _expectTrue(html.contains("story"))
    _expectTrue(html.contains("animation"))
    let animationValue = optionValue(tree.renderNode, label: "animation")
    _expectNotNil(animationValue)
    tree.dispatch(event: "change", value: animationValue ?? "")
    _expectEqual(selection, .animation)
    _ = tree.update(picker)
    let selectedValue = optionValue(tree.renderNode, label: "animation")
    _expectEqual(selectedValue, animationValue)
    _expectTrue(tree.renderNode.htmlDescription.contains("selected=\"selected\""))
  }

  @Test
  func testSliderExposesSemanticRangeValues() {
    let slider = Slider(value: .constant(0.5), in: 0...1, step: 0.1)
    let html = StaticHTMLFiberRenderer().render(slider)
    _expectTrue(html.contains("class=\"slider-control\""))
    _expectTrue(html.contains("aria-valuemin=\"0\""))
    _expectTrue(html.contains("aria-valuemax=\"1\""))
    _expectTrue(html.contains("aria-valuenow=\"0.5\""))
    _expectTrue(html.contains("aria-label=\"Value\""))
    _expectTrue(html.contains("--val: 50%"))
    _expectTrue(html.contains("--slider-value: 50%"))
  }

  @Test
  func testDatePickerEmitsAndConsumesISODateValue() {
    var date = Date(timeIntervalSince1970: 0)
    let binding = Binding<Date>(get: { date }, set: { date = $0 })
    let picker = DatePicker("Birthday", selection: binding, displayedComponents: .date)
    let tree = FiberTree(picker)

    _expectTrue(tree.renderNode.htmlDescription.contains("type=\"date\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("value=\"1970-01-01\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("data-date-picker=\"true\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("date-picker-trigger"))
    // A date-only trigger shows the canonical, locale-independent value (see `_dateDisplayValue`).
    _expectTrue(tree.renderNode.htmlDescription.contains("<span class=\"date-picker-value\">1970-01-01</span>"))
    tree.dispatch(event: "change", value: "2024-02-29")
    _expectNotEqual(date.timeIntervalSince1970, 0)
    _ = tree.update(picker)
    _expectTrue(tree.renderNode.htmlDescription.contains("value=\"2024-02-29\""))
  }

  @Test
  func testDisabledPropagatesAndSuppressesControlEvents() {
    var taps = 0
    let view = Button("Save") { taps += 1 }.disabled(true)
    let tree = FiberTree(view)
    tree.dispatch(event: "click")

    _expectEqual(taps, 0)
    _expectTrue(tree.renderNode.htmlDescription.contains("disabled=\"disabled\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("aria-disabled=\"true\""))
  }

  @Test
  func testHoverReportsEnterAndLeave() {
    var states: [Bool] = []
    let tree = FiberTree(Text("Hover").onHover { states.append($0) })
    tree.dispatch(event: "mouseenter")
    tree.dispatch(event: "mouseleave")
    _expectEqual(states, [true, false])
  }

  @Test
  func testBuiltinAndCustomHoverEffectsSerializeBothPhases() {
    let custom = Button("Preview") {}
      .frame(width: 120, height: 44)
      .hoverEffect { effect, isActive, proxy in
        effect
          .scaleEffect(isActive ? (proxy.size.width > 0 ? 1.1 : 1.05) : 1)
          .opacity(isActive ? 1 : 0.8)
          .animation(.easeOut(duration: 0.16)) { $0 }
      }
    let customHTML = FiberTree(custom).renderNode.htmlDescription
    _expectTrue(customHTML.contains("data-hover-effect=\"custom\""))
    _expectTrue(customHTML.contains("data-hover-has-opacity=\"true\""))
    _expectTrue(customHTML.contains("--hover-rest-scale: 1.0 1.0"))
    _expectTrue(customHTML.contains("--hover-active-scale: 1.1 1.1"))
    _expectTrue(customHTML.contains("--hover-active-opacity: 1.0"))

    let builtinHTML = FiberTree(Button("Lift") {}.hoverEffect(.lift)).renderNode.htmlDescription
    _expectTrue(builtinHTML.contains("data-hover-effect=\"lift\""))
    _expectTrue(builtinHTML.contains("data-hover-enabled=\"true\""))
  }

  @Test
  func testDefaultHoverEffectGroupDisableAndListRowControls() {
    let view = VStack {
      Button("One") {}.listRowHoverEffect(.highlight)
      Button("Two") {}.hoverEffect(.lift).hoverEffectDisabled()
    }
    .defaultHoverEffect(.automatic)
    .hoverEffectGroup()
    let html = FiberTree(view).renderNode.htmlDescription

    _expectTrue(html.contains("data-hover-group-root=\"implicit:"))
    _expectTrue(html.contains("data-hover-source=\"default\""))
    _expectTrue(html.contains("data-list-row-hover-effect=\"highlight\""))
    _expectTrue(html.contains("data-hover-disabled=\"true\""))
    _expectTrue(html.contains("data-hover-enabled=\"false\""))
    _expectTrue(html.contains("data-hover-group=\"implicit:"))
  }

  @Test
  func testNamespaceHoverGroupsHaveStableSharedIdentity() {
    let namespace = Namespace()
    let first = HoverEffectGroup(id: "settings-row", in: namespace.wrappedValue)
    let second = HoverEffectGroup(id: "settings-row", in: namespace.wrappedValue)
    let activation = GroupHoverEffect.hoverEffectGroup(id: "settings-row", in: namespace.wrappedValue)
    let custom = ReusableTestHoverEffect()
      .hoverEffect(.lift, in: first)
      .hoverEffectGroup(id: "custom-row", in: namespace.wrappedValue)
    let html = FiberTree(Button("Grouped") {}.hoverEffect(custom)).renderNode.htmlDescription

    _expectEqual(first.id, second.id)
    _expectEqual(first.behavior, .activatesGroup)
    _expectEqual(HoverEffectGroup(id: first.id, behavior: .preservesGroup).behavior, .preservesGroup)
    _expectEqual(activation._hoverEffectGroup?.id, first.id)
    _expectTrue(html.contains(":custom-row\""))
    _expectTrue(html.contains("--hover-rest-opacity: 0.5"))
    _expectTrue(html.contains("--hover-active-opacity: 1.0"))
  }

  @Test
  func testLongPressReportsPressingStateAndReleaseAction() {
    var states: [Bool] = []
    var ended = 0
    let tree = FiberTree(
      Text("Press")
        .onLongPressGesture(minimumDuration: 0, perform: { ended += 1 }, onPressingChanged: { states.append($0) })
    )
    tree.dispatch(event: "pointerdown")
    tree.dispatch(event: "pointerup")
    _expectEqual(states, [true, false])
    _expectEqual(ended, 1)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-long-press=\"true\""))
  }

  @Test
  func testDisclosureGroupBindingTogglesThroughFiberEvent() {
    var expanded = false
    let binding = Binding<Bool>(get: { expanded }, set: { expanded = $0 })
    let view = DisclosureGroup("Details", isExpanded: binding) { Text("Content") }
    let tree = FiberTree(view)
    tree.dispatch(event: "click")
    _expectTrue(expanded)
    _ = tree.update(view)
    _expectTrue(tree.renderNode.htmlDescription.contains("open=\"open\""))
  }

  @Test
  func testAnimationAndTransitionAreRenderedAsComposableMetadata() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Animated")
        .animation(.easeInOut, value: true)
        .transition(.opacity)
    )
    _expectTrue(html.contains("data-animation=\"ease-in-out\""))
    _expectTrue(html.contains("data-transition=\"opacity\""))
    // The states the host plays when the view is inserted or removed in an animated commit; nothing transitions otherwise.
    _expectTrue(html.contains("data-transition-insert=\"opacity:0\""))
    _expectTrue(html.contains("data-transition-remove=\"opacity:0\""))
    _expectTrue(!html.contains("transition:"))
  }

  @Test
  func testAnimationFactoryOverloadsAndWithAnimationAreSwiftUIShaped() {
    let spring = Animation.spring(response: 0.32, dampingFraction: 0.8, blendDuration: 0.05)
    // Springs play their own curve, sampled into a CSS linear() easing (SpringMotion.swift).
    _expectTrue(spring.cssValue.contains("linear("))
    _expectTrue(spring.cssValue.contains("ms"))

    let interpolating = Animation.interpolatingSpring(stiffness: 170, damping: 15)
    _expectTrue(interpolating.cssValue.contains("linear("))
    let curve = Animation.timingCurve(0.58, 0.02, 0.18, 1, duration: 0.72)
    _expectTrue(curve.cssValue.contains("720ms"))
    _expectTrue(curve.cssValue.contains("cubic-bezier(0.58"))
    _expectTrue(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true).cssValue.contains("infinite"))
    _expectTrue(Animation.easeOut(duration: 0.18).delay(0.1).cssValue.contains("100ms"))

    let result = withAnimation(.snappy(duration: 0.3, extraBounce: 0.01)) { 42 }
    _expectEqual(result, 42)
  }

  @Test
  func testContentShapeProducesHitRegionMetadataAndCSSGeometry() {
    let circleHTML = StaticHTMLFiberRenderer().render(
      Button("Circle") {}.contentShape(Circle())
    )
    _expectTrue(circleHTML.contains("data-content-shape=\"circle\""))
    _expectTrue(circleHTML.contains("clip-path: circle(50% at 50% 50%);"))

    let roundedHTML = StaticHTMLFiberRenderer().render(
      Text("Rounded").contentShape(RoundedRectangle(cornerRadius: 12))
    )
    _expectTrue(roundedHTML.contains("data-content-shape=\"rounded-rectangle\""))
    _expectTrue(roundedHTML.contains("border-radius: 12px;"))

    let evenOddHTML = StaticHTMLFiberRenderer().render(
      Text("Even odd").contentShape(Rectangle(), eoFill: true)
    )
    _expectTrue(evenOddHTML.contains("data-content-shape-fill-rule=\"evenodd\""))
  }

  @Test
  func testStepperRendersAccessibleControlsAndUpdatesIntegerBinding() {
    var value = 1
    let binding = Binding<Int>(get: { value }, set: { value = $0 })
    let stepper = Stepper("Quantity", value: binding, in: 0...2)
    let tree = FiberTree(stepper)
    let html = tree.renderNode.htmlDescription

    _expectTrue(html.contains("class=\"stepper-control\""))
    _expectTrue(html.contains("role=\"spinbutton\""))
    _expectTrue(html.contains("aria-valuenow=\"1\""))
    // SwiftUI's Stepper never draws its value: the spinbutton keeps it for assistive technology and holds no text.
    _expectTrue(html.contains("class=\"stepper-value\""))
    _expectTrue(!html.contains(">1</span>"))
    _expectTrue(html.contains("aria-label=\"Decrease\""))
    _expectTrue(html.contains("aria-label=\"Increase\""))

    let buttons = findElements(named: "button", in: tree.renderNode)
    _expectEqual(buttons.count, 2)
    buttons[1].events["click"]?.action()
    _expectEqual(value, 2)
    buttons[1].events["click"]?.action()
    _expectEqual(value, 2, "Stepper must clamp at the upper bound")
  }

  @Test
  func testFocusStateModifierRoundTripsFocusAndBlur() {
    struct FocusedView: View {
      @FocusState private var focused: Bool
      var body: some View {
        TextField("Name", text: .constant("")).focused($focused)
      }
    }
    let focusedViewHTML = StaticHTMLFiberRenderer().render(FocusedView())
    _expectTrue(focusedViewHTML.contains("data-focus-value=\"true\""))

    struct OptionalFocusedView: View {
      enum Field: Hashable { case name }
      @FocusState private var field: Field?
      var body: some View {
        TextField("Name", text: .constant("")).focused($field, equals: .name)
      }
    }
    _expectTrue(StaticHTMLFiberRenderer().render(OptionalFocusedView()).contains("data-focus-value"))

    var focused = false
    let binding = Binding<Bool>(get: { focused }, set: { focused = $0 })
    let tree = FiberTree(TextField("Name", text: .constant("")).focused(binding))
    _expectTrue(tree.renderNode.htmlDescription.contains("data-focus-value=\"true\""))

    tree.dispatch(event: "focus")
    _expectTrue(focused)
    tree.dispatch(event: "blur")
    _expectFalse(focused)
  }

  @Test
  func testMenuRendersNativeDisclosureAndMenuLandmark() {
    let tree = FiberTree(Menu("Actions") {
      Button("Edit") {}
      Button("Delete", role: .destructive) {}
    })
    let html = tree.renderNode.htmlDescription

    _expectTrue(html.contains("class=\"menu-popup\""))
    _expectTrue(html.contains("role=\"button\""))
    _expectTrue(html.contains("role=\"menu\""))
    _expectTrue(html.contains("Edit"))
    _expectTrue(html.contains("data-role=\"destructive\""))
  }

  @Test
  func testColorPickerUsesNativeColorInputAndBinding() {
    var color = Color.red
    let binding = Binding<Color>(get: { color }, set: { color = $0 })
    let picker = ColorPicker("Accent", selection: binding, supportsOpacity: false)
    let tree = FiberTree(picker)
    let html = tree.renderNode.htmlDescription

    _expectTrue(html.contains("type=\"color\""))
    _expectTrue(html.contains("value=\"#ff3b30\""))
    _expectTrue(html.contains("data-supports-opacity=\"false\""))
    tree.dispatch(event: "change", value: "#336699")
    _expectEqual(color.cssValue, "#336699")
  }

  @Test
  func testAsyncImageUsesFiberLoadAndErrorPhases() {
    let imageURL = URL(string: "https://example.com/image.png")!
    let view = AsyncImage(url: imageURL) { phase in
      if let image = phase.image {
        image
      } else if phase.error != nil {
        Text("Failed")
      } else {
        Text("Loading")
      }
    }
    let tree = FiberTree(view)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-async-image=\"true\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("Loading"))
    guard let loader = tree.findNode(withEvent: "load") else {
      return _fail("AsyncImage should expose a host load event")
    }
    tree.dispatch(event: "load", on: loader)
    _ = tree.update(view)
    _expectTrue(tree.renderNode.htmlDescription.contains("image.png"))
    _expectFalse(tree.renderNode.htmlDescription.contains("Loading"))
  }

  @Test
  func testAsyncImageStartsNewPhaseWhenURLChangesWithinSameIdentity() {
    let firstURL = URL(string: "https://example.com/first.png")!
    let secondURL = URL(string: "https://example.com/second.png")!
    let makeView: (URL) -> AnyView = { url in
      AnyView(AsyncImage(url: url) { phase in
        if let image = phase.image {
          image
        } else {
          Text("Loading")
        }
      })
    }
    let first = makeView(firstURL)
    let tree = FiberTree(first)
    let firstLoader = tree.findNode(withEvent: "load")
    guard let firstLoader else { return _fail("first AsyncImage URL should expose a load event") }
    tree.dispatch(event: "load", on: firstLoader)
    _ = tree.update(first)
    #expect(tree.renderNode.htmlDescription.contains("first.png"), "the first request should render its loaded image")

    let second = makeView(secondURL)
    _ = tree.update(second)
    let refreshedHTML = tree.renderNode.htmlDescription
    #expect(refreshedHTML.contains("Loading"), "a changed URL should return to its placeholder")
    #expect(refreshedHTML.contains("second.png"), "the new URL should start loading")
    #expect(!refreshedHTML.contains("first.png"), "the old image must leave the visible tree")

    guard let secondLoader = tree.findNode(withEvent: "load") else {
      return _fail("refreshed AsyncImage URL should expose a load event")
    }
    #expect(secondLoader.attributes["src"]?.contains("second.png") == true, "the registered load callback should belong to the refreshed URL")
    tree.dispatch(event: "load", on: secondLoader)
    _ = tree.update(second)
    #expect(tree.renderNode.htmlDescription.contains("second.png"), "the second request should render its loaded image")
    #expect(!tree.renderNode.htmlDescription.contains("Loading"), "the second phase should finish loading")
  }

  @Test
  func testGaugeAndLabeledContentRenderSemanticValues() {
    let gauge = Gauge(value: 3, in: 0...10, label: { Text("Progress") })
    let gaugeHTML = StaticHTMLFiberRenderer().render(gauge)
    _expectTrue(gaugeHTML.contains("role=\"meter\""))
    _expectTrue(gaugeHTML.contains("aria-valuemin=\"0\""))
    _expectTrue(gaugeHTML.contains("aria-valuemax=\"10\""))
    _expectTrue(gaugeHTML.contains("aria-valuenow=\"3\""))

    let labeledHTML = StaticHTMLFiberRenderer().render(LabeledContent("Status", value: "Ready"))
    _expectTrue(labeledHTML.contains("class=\"labeled-content\""))
    _expectTrue(labeledHTML.contains("role=\"term\""))
    _expectTrue(labeledHTML.contains("role=\"definition\""))
    _expectTrue(labeledHTML.contains("Ready"))
  }

  @Test
  func testGroupBoxUsesFieldsetAndSearchableUpdatesBinding() {
    let groupHTML = StaticHTMLFiberRenderer().render(
      GroupBox("Account") { Text("Signed in") }
    )
    _expectTrue(groupHTML.contains("<fieldset"))
    _expectTrue(groupHTML.contains("<legend"))
    _expectTrue(groupHTML.contains("Account"))

    var query = ""
    let binding = Binding<String>(get: { query }, set: { query = $0 })
    let tree = FiberTree(Text("Results").searchable(text: binding, placement: .sidebar, prompt: "Find"))
    let html = tree.renderNode.htmlDescription
    _expectTrue(html.contains("role=\"search\""))
    _expectTrue(html.contains("type=\"search\""))
    _expectTrue(html.contains("data-search-placement=\"sidebar\""))
    _expectTrue(html.contains("placeholder=\"Find\""))
    tree.dispatch(event: "input", value: "Swift")
    _expectEqual(query, "Swift")
  }

  @Test
  func testMissingComponentConveniencesKeepSwiftUITrailingClosureShapes() {
    let imageURL = URL(string: "https://example.com/image.png")!
    _ = AsyncImage(url: imageURL)
    _ = AsyncImage(url: imageURL) { image in image } placeholder: { ProgressView() }
    _ = GroupBox {
      Text("Content")
    } label: {
      Text("Title")
    }
    _ = LabeledContent {
      Text("Value")
    } label: {
      Text("Label")
    }
    var query = ""
    let binding = Binding<String>(get: { query }, set: { query = $0 })
    let search = Text("Results").searchable(
      text: binding,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: Text("Find")
    )
    let searchHTML = StaticHTMLFiberRenderer().render(search)
    _expectTrue(searchHTML.contains("data-search-placement=\"navigationBarDrawer\""))
    _expectTrue(searchHTML.contains("search-input"))
  }

  @Test
  func testNavigationSplitViewRendersTwoColumnsAndVisibility() {
    var visibility = NavigationSplitViewVisibility.all
    let binding = Binding<NavigationSplitViewVisibility>(get: { visibility }, set: { visibility = $0 })
    let view = NavigationSplitView(columnVisibility: binding) {
      Text("Sidebar")
    } detail: {
      Text("Detail")
    }
    let tree = FiberTree(view)
    var html = tree.renderNode.htmlDescription

    _expectTrue(html.contains("data-column-count=\"2\""))
    _expectTrue(html.contains("data-navigation-column=\"sidebar\""))
    _expectTrue(html.contains("data-navigation-column=\"detail\""))
    _expectFalse(html.contains("data-navigation-column=\"content\""))

    visibility = .detailOnly
    _ = tree.update(view)
    html = tree.renderNode.htmlDescription
    _expectTrue(html.contains("data-column-visibility=\"detailOnly\""))
    _expectTrue(html.contains("navigation-sidebar"))
    _expectTrue(html.contains("data-column-hidden=\"true\""))

    let threeColumnHTML = StaticHTMLFiberRenderer().render(
      NavigationSplitView {
        Text("Sidebar")
      } content: {
        Text("Content")
      } detail: {
        Text("Detail")
      }
    )
    _expectTrue(threeColumnHTML.contains("data-column-count=\"3\""))
    _expectTrue(threeColumnHTML.contains("data-navigation-column=\"content\""))
  }

  private func findElements(named tag: String, in node: _RenderNode) -> [_RenderNode] {
    var result: [_RenderNode] = []
    if node.kind == .element(tag) { result.append(node) }
    for child in node.children { result.append(contentsOf: findElements(named: tag, in: child)) }
    return result
  }

  @Test
  func testObservableObjectInvalidatesOwningFiberTree() async {
    final class Model: ObservableObject {
      var value = 0
      func set(_ value: Int) {
        self.value = value
        objectWillChange.send()
      }
    }
    struct ModelView: View {
      @ObservedObject var model: Model
      var body: some View { Text("Value: \(model.value)") }
    }

    let model = Model()
    let tree = FiberTree(ModelView(model: model))
    _expectTrue(tree.renderNode.htmlDescription.contains("Value: 0"))
    model.set(7)
    await _settleObservedRefreshes()
    _expectTrue(tree.renderNode.htmlDescription.contains("Value: 7"))
    _expectFalse(tree.lastMutations.isEmpty)
  }

  @Test
  func testPublishedPropertyAutomaticallyNotifiesObservableFiber() async {
    final class Model: ObservableObject {
      @Published var value = 0
    }
    struct ModelView: View {
      @ObservedObject var model: Model
      var body: some View { Text("Published: \(model.value)") }
    }

    let model = Model()
    let tree = FiberTree(ModelView(model: model))
    model.value = 9
    // Combine announces the change before storing it; the refresh runs in the next turn, as in SwiftUI.
    await Task.yield()
    _expectTrue(tree.renderNode.htmlDescription.contains("Published: 9"))
  }

  @Test
  func testStorageAdapterPersistsSupportedScalarValuesAcrossWrappers() {
    var values: [String: String] = [:]
    StorageRuntime.install(StorageAdapter(
      read: { values[$0] },
      write: { values[$0] = $1 }
    ))
    defer { StorageRuntime.install(nil) }

    let first = AppStorage(wrappedValue: 0, "partial-test-counter")
    _expectEqual(first.wrappedValue, 0)
    first.wrappedValue = 12
    let second = AppStorage(wrappedValue: 0, "partial-test-counter")
    _expectEqual(second.wrappedValue, 12)
  }

  @Test
  func testTabViewCustomizationPersistsThroughStorageAdapter() {
    var values: [String: String] = [:]
    StorageRuntime.install(StorageAdapter(
      read: { values[$0] },
      write: { values[$0] = $1 }
    ))
    defer { StorageRuntime.install(nil) }

    let first = AppStorage(wrappedValue: TabViewCustomization(), "partial-test-tabs")
    first.wrappedValue = TabViewCustomization(
      hiddenTabs: ["account|profile"],
      order: ["inbox", "account|profile"]
    )
    let second = AppStorage(wrappedValue: TabViewCustomization(), "partial-test-tabs")
    _expectEqual(second.wrappedValue.hiddenTabs, ["account|profile"])
    _expectEqual(second.wrappedValue.order, ["inbox", "account|profile"])
  }

  @Test
  func testAppTitleRuntimeRetainsHostTitleForPlatformAdapters() {
    AppTitleRuntime.set("SwiftUIWeb test")
    _expectEqual(AppTitleRuntime.current, "SwiftUIWeb test")
    AppTitleRuntime.current = nil
  }

  @Test
  func testNavigationLinksOwnDefaultPreventionButButtonsDoNot() {
    enum Route: Hashable { case detail }
    struct Root: View {
      @State var path = NavigationPath()
      var body: some View {
        NavigationStack(path: $path) {
          VStack {
            NavigationLink("Detail", value: Route.detail)
            Button("Action") {}
          }
          .navigationDestination(for: Route.self) { _ in Text("Detail") }
        }
      }
    }

    let tree = FiberTree(Root())
    let navigationLink = tree.findNode(withEvent: "click")
    _expectEqual(navigationLink?.events["click"]?.preventsDefault, true)
    func findButton(_ node: _RenderNode) -> _RenderNode? {
      if node.kind == .element("button") { return node }
      for child in node.children {
        if let button = findButton(child) { return button }
      }
      return nil
    }
    let button = findButton(tree.renderNode)
    _expectEqual(button?.events["click"]?.preventsDefault, false)
  }

  @Test
  func testNavigationHistoryEnvironmentRestoresTypedPath() {
    enum Route: Hashable { case detail }
    final class Recorder: NavigationHistoryAdapter {
      var operations: [NavigationHistoryOperation] = []
      var snapshots: [NavigationPath] = []
      var callback: ((NavigationPath) -> Void)?
      func apply(_ operation: NavigationHistoryOperation) { operations.append(operation) }
      func update(_ navigationPath: NavigationPath) { snapshots.append(navigationPath._historySnapshot()) }
      func observe(_ callback: @escaping (NavigationPath) -> Void) { self.callback = callback }
    }
    struct Root: View {
      @State var path = NavigationPath()
      var body: some View {
        NavigationStack(path: $path) {
          NavigationLink("Detail", value: Route.detail)
            .navigationDestination(for: Route.self) { _ in Text("Detail") }
        }
      }
    }

    let recorder = Recorder()
    let root = Root()
    var environment = EnvironmentValues()
    environment.navigationHistory = recorder
    let tree = FiberTree(root, environment: environment)
    root.path.append(Route.detail)
    _ = tree.update(root, environment: environment)
    _expectEqual(recorder.operations.last, .push(path: "/detail"))
    _expectEqual(recorder.snapshots.last?.count, 1)

    recorder.callback?(NavigationPath([Route.detail]))
    _expectEqual(root.path.count, 1)
  }
}
