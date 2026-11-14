import Testing
import SwiftUIWeb
@testable @_spi(Renderer) import SwiftUIWebCore
@testable @_spi(Renderer) import SwiftUIWebFeatures
import Foundation

@Suite
@MainActor
struct CoreModifierContractTests {
  private final class SettingsModel {
    let title: String
    init(title: String) { self.title = title }
  }

  private struct EnvironmentObjectReader: View {
    @EnvironmentObject private var model: SettingsModel
    var body: some View { Text(model.title) }
  }

  private struct ComposedModifier: ViewModifier {
    func body(content: Content) -> some View {
      content.padding(6).accessibilityLabel("Composed content")
    }
  }

  private struct InheritedPaint: ShapeStyle {}

  private struct ContractCustomShape: InsettableShape {
    func path(in rect: CGRect) -> Path { Path(rect) }
    func inset(by amount: CGFloat) -> ContractCustomShape { self }
  }

  private final class ItemDismissCounts {
    var sheet = 0
    var cover = 0
    var popover = 0
  }

  private struct ItemDismissButton: View {
    @Environment(\.dismiss) private var dismiss
    let title: String

    var body: some View {
      Button(title) { dismiss() }
    }
  }

  @Test
  func actionFocusAndPointerModifiersDispatchTheirPublicCallbacks() throws {
    var submits = 0
    var focusCallbacks = 0
    var blurCallbacks = 0
    var hoverChanges: [Bool] = []
    var focused = false
    let view = VStack {
      Text("Events")
        .onSubmit { submits += 1 }
        .onFocus { focusCallbacks += 1 }
        .onBlur { blurCallbacks += 1 }
      Text("Pointer").onHover { hoverChanges.append($0) }
      Text("Bound focus").focused(Binding(get: { focused }, set: { focused = $0 }))
    }
    let tree = FiberTree(view)
    let events = try #require(tree.findNode(withEvent: "submit"))
    tree.dispatch(event: "submit", on: events)
    tree.dispatch(event: "focus", on: events)
    tree.dispatch(event: "blur", on: events)
    #expect(events.events["submit"]?.preventsDefault == true)
    #expect(submits == 1)
    #expect(focusCallbacks == 1)
    #expect(blurCallbacks == 1)

    let pointer = try #require(tree.findNode(withEvent: "mouseenter"))
    tree.dispatch(event: "mouseenter", on: pointer)
    tree.dispatch(event: "mouseleave", on: pointer)
    #expect(hoverChanges == [true, false])

    let focusTree = FiberTree(Text("Bound focus").focused(Binding(get: { focused }, set: { focused = $0 })))
    let boundFocus = try #require(focusTree.findNode(withEvent: "focus"))
    focusTree.dispatch(event: "focus", on: boundFocus)
    #expect(focused)
    focusTree.dispatch(event: "blur", on: boundFocus)
    #expect(!focused)
  }

  @Test
  func framePaddingTextAndAccessibilityModifiersExposeSemanticOutput() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Text("Label")
          .accessibilityLabel(Text("Friendly label"))
          .accessibilityIdentifier("friendly-label")
          .bold()
          .hidden()
          .clipped()
        Text("Fixed").frame(width: 80, height: 24, alignment: .bottomTrailing)
        Text("Constrained").frame(width: 60, height: 24).frame(
          maxWidth: 120, maxHeight: 48, alignment: .topLeading
        )
        Text("Flexible").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        Text("Ideal").frame(
          minWidth: 30, idealWidth: 60, maxWidth: 120,
          minHeight: 12, idealHeight: 24, maxHeight: 48,
          alignment: .leading
        )
        Text("Edges").padding([.top, .leading, .bottom, .trailing], 4)
        Text("No edges").padding([])
        Text("Clamped").lineLimit(2).multilineTextAlignment(.trailing)
        Text("Unlimited").lineLimit(nil).fixedSize(horizontal: false, vertical: true)
      }
    )

    #expect(html.contains("aria-label=\"Friendly label\""))
    #expect(html.contains("data-testid=\"friendly-label\""))
    #expect(html.contains("font-weight: 700"))
    #expect(html.contains("display: none"))
    #expect(html.contains("overflow: hidden"))
    #expect(html.contains("width: 80px"))
    #expect(html.contains("height: 24px"))
    #expect(html.contains("max-width: 120px"))
    #expect(html.contains("data-frame-max-w=\"inf\""))
    #expect(html.contains("--ideal-width: 60px"))
    #expect(html.contains("padding-inline-start: 4px"))
    #expect(html.contains("-webkit-line-clamp: 2"))
    #expect(html.contains("text-align: right"))
    #expect(html.contains("data-fixed-x=\"false\""))
  }

  @Test
  func backgroundsOverlaysShapeStylesBadgesAndTabMetadataCompose() {
    let style = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Text("Background view")
          .background(alignment: .topLeading) { Circle().fill(Color.blue) }
        Text("Overlay").overlay(alignment: .bottomTrailing) { Text("Badge") }
        Text("Shape background").background(style, in: .rect(cornerRadius: 8))
        Text("Shape style background").background(style)
        Text("Gradient foreground").foregroundStyle(style)
        Group {
          Text("Zero badge").badge(0)
          Text("No integer badge").badge(0)
          Text("Empty badge").badge(Optional<String>.none)
          Text("String badge").badge("NEW")
          Text("Text badge").badge(Text("5"))
          Text("Substring badge").badge("hot"[...])
        }
        Text("Tab").tabItem { Label("Home", systemImage: "house") }
          .customizationID("home-tab")
          .badge(3)
      }
      .tabViewStyle(.sidebarAdaptable)
      .tabViewCustomization(.constant(TabViewCustomization(hiddenTabs: ["settings"], order: ["home-tab"])))
    )

    #expect(html.contains("data-background-shape=\"rounded-rectangle-8\""))
    #expect(html.contains("data-background-style=\"linear-gradient"))
    #expect(html.contains("data-foreground-style=\"linear-gradient"))
    #expect(html.contains("data-tab-item=\"true\""))
    #expect(html.contains("data-tab-label=\"Home\""), "the icon's fallback glyph is not part of the title")
    #expect(html.contains("data-tab-system-image=\"house\""))
    #expect(html.contains("data-tab-customization-id=\"home-tab\""))
    #expect(!html.contains("data-badge=\"0\""), "a count of zero shows no badge, as in SwiftUI")
    #expect(html.contains("data-badge=\"NEW\""))
    #expect(html.contains("data-badge=\"5\""))
    #expect(html.contains("data-badge=\"hot\""))
    #expect(html.contains("data-badge=\"3\""))
    #expect(html.contains("data-tab-style=\"sidebar-adaptable\""))
    #expect(html.contains("data-tab-customization=\"true\""))
  }

  @Test
  func presentationOverloadsRenderTheirMessageActionsAndDismissalSurface() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Text("Popover source")
          .popover(isPresented: .constant(true)) { Text("Popover content") }
        Text("Message alert source")
          .alert("Information", isPresented: .constant(true), actions: { Text("OK") }, message: { Text("Alert message") })
        Text("Title-only alert source")
          .alert("Notice", isPresented: .constant(true)) { Text("OK") }
        Text("Confirmation source")
          .confirmationDialog(
            "Choose",
            isPresented: .constant(true),
            actions: { Button("Confirm") {} },
            message: { Text("Confirmation message") }
          )
        Text("Confirmation without message")
          .confirmationDialog("Quick choice", isPresented: .constant(true)) {
            Button("Continue") {}
          }
      }
    )

    #expect(html.contains("data-presentation=\"popover\""))
    #expect(html.contains("Popover content"))
    #expect(html.contains("data-presentation=\"alert\""))
    #expect(html.contains("Alert message"))
    #expect(html.contains("Notice"))
    #expect(html.contains("data-presentation=\"confirmation-dialog\""))
    #expect(html.contains("Confirmation message"))
    #expect(html.contains("Confirm"))
    #expect(html.contains("Quick choice"))
    #expect(html.contains("Continue"))
  }

  @Test
  func itemPresentationsDismissFromHostAndContentAndCallAvailableOnDismissCallbacks() throws {
    struct Item: Identifiable {
      let id: Int
    }

    struct Root: View {
      @State var sheet: Item? = Item(id: 1)
      @State var cover: Item? = Item(id: 2)
      @State var popover: Item? = Item(id: 3)
      let counts: ItemDismissCounts

      var body: some View {
        Text("Source")
          .sheet(item: $sheet, onDismiss: { counts.sheet += 1 }) { item in
            ItemDismissButton(title: "Dismiss sheet \(item.id)")
          }
          .fullScreenCover(item: $cover, onDismiss: { counts.cover += 1 }) { item in
            ItemDismissButton(title: "Dismiss cover \(item.id)")
          }
          .popover(item: $popover) { item in
            ItemDismissButton(title: "Dismiss popover \(item.id)")
          }
      }
    }

    let counts = ItemDismissCounts()
    let root = Root(counts: counts)
    let tree = FiberTree(root)

    func dismissFromHost(style: String, itemID: Int, expectedCount: Int) {
      guard let host = findNode(tree.renderNode, where: {
        $0.attributes["data-presentation"] == style && $0.events["presentation-dismiss"] != nil
      }) else {
        Issue.record("Expected a (style) presentation host")
        return
      }
      #expect(host.htmlDescription.contains("\(itemID)"))
      tree.dispatch(event: "presentation-dismiss", on: host)
      #expect(findNode(tree.renderNode) { $0.attributes["data-presentation"] == style } == nil)
      switch style {
      case "sheet": #expect(counts.sheet == expectedCount)
      case "full-screen-cover": #expect(counts.cover == expectedCount)
      default: #expect(counts.popover == expectedCount)
      }
    }

    func dismissFromContent(style: String, title: String, expectedCount: Int) throws {
      switch style {
      case "sheet": root.sheet = Item(id: 11)
      case "full-screen-cover": root.cover = Item(id: 12)
      default: root.popover = Item(id: 13)
      }
      _ = tree.update(root)
      let button = try #require(findNode(tree.renderNode) {
        $0.events["click"] != nil && $0.htmlDescription.contains(title)
      })
      tree.dispatch(event: "click", on: button)
      switch style {
      case "sheet":
        #expect(root.sheet?.id == nil)
        #expect(counts.sheet == expectedCount)
      case "full-screen-cover":
        #expect(root.cover?.id == nil)
        #expect(counts.cover == expectedCount)
      default:
        #expect(root.popover?.id == nil)
        #expect(counts.popover == expectedCount)
      }
    }

    dismissFromHost(style: "sheet", itemID: 1, expectedCount: 1)
    try dismissFromContent(style: "sheet", title: "Dismiss sheet 11", expectedCount: 2)
    dismissFromHost(style: "full-screen-cover", itemID: 2, expectedCount: 1)
    try dismissFromContent(style: "full-screen-cover", title: "Dismiss cover 12", expectedCount: 2)
    dismissFromHost(style: "popover", itemID: 3, expectedCount: 0)
    try dismissFromContent(style: "popover", title: "Dismiss popover 13", expectedCount: 0)
  }

  @Test
  func shapePaintAndContentShapeOverloadsKeepTheirVectorSemantics() {
    let gradient = Gradient(stops: [
      .init(color: .red, location: 0),
      .init(color: .blue, location: 1)
    ])
    let angular: AngularGradient = .conicGradient(gradient, center: .center, angle: .zero)
    let linear = LinearGradient(stops: gradient.stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    let radial = RadialGradient(stops: gradient.stops, center: .center, startRadius: 2, endRadius: 12)
    #expect(Gradient(colors: []).stops.isEmpty)
    #expect(Gradient(colors: [.red]).stops.first?.location == 0)
    #expect(angular.gradient == gradient)
    #expect(linear.gradient == gradient)
    #expect(radial.gradient == gradient)

    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Circle().strokeBorder(Color.red, lineWidth: 3)
        RoundedRectangle(cornerRadius: 8).strokeBorder(lineWidth: 2)
        Rectangle().strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 4, dash: [2, 1]))
        Circle().fill(InheritedPaint())
        Text("Capsule target").contentShape(Capsule())
        Text("Rounded target").contentShape(RoundedRectangle(cornerRadius: 6), eoFill: true)
        linear
        radial
        angular
        Text("Arbitrary direction").background(
          LinearGradient(colors: [.red, .blue], startPoint: UnitPoint(x: 0.2, y: 0.3), endPoint: UnitPoint(x: 0.8, y: 0.6))
        )
      }
    )

    #expect(html.contains("stroke-width=\"3\""))
    #expect(html.contains("stroke-width=\"2\""))
    #expect(html.contains("stroke-dasharray=\"2 1\""))
    #expect(html.contains("data-shape-paint=\"currentColor\""))
    #expect(html.contains("data-content-shape=\"capsule\""))
    #expect(html.contains("data-content-shape=\"rounded-rectangle\""))
    #expect(html.contains("data-content-shape-fill-rule=\"evenodd\""))
    #expect(html.contains("linearGradient"))
    #expect(html.contains("radialGradient"))
    #expect(html.contains("conic-gradient"))
  }

  @Test
  func modelEnvironmentInjectionUsesTheTypedObjectChannel() {
    let html = StaticHTMLFiberRenderer().render(
      EnvironmentObjectReader().environmentObject(SettingsModel(title: "Network settings"))
    )
    #expect(html.contains("Network settings"))
  }

  @Test
  func customViewModifiersComposeTheirBodyAroundTheOriginalContent() {
    let html = StaticHTMLFiberRenderer().render(Text("Modified").modifier(ComposedModifier()))
    #expect(html.contains("Modified"))
    #expect(html.contains("aria-label=\"Composed content\""))
    #expect(html.contains("padding: 6px"))
  }

  @Test
  func explicitHoverGroupsAndListRowControlsStaySemantic() {
    let namespace = Namespace()
    let group = HoverEffectGroup(id: "settings", in: namespace.wrappedValue, behavior: .preservesGroup)
    let tree = FiberTree(
      VStack {
        Button("Grouped") {}
          .hoverEffect(.highlight, in: group)
          .listRowHoverEffect(.lift)
          .listRowHoverEffectDisabled()
        Button("No group") {}.hoverEffect(EmptyHoverEffect(), in: nil, isEnabled: false)
        Button("Group root") {}.hoverEffectGroup(group)
        Button("Implicit root") {}.hoverEffectGroup()
        Button("Named root") {}.hoverEffectGroup(
          id: "named", in: namespace.wrappedValue, behavior: .preservesGroup
        )
      }
    )
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("data-hover-group=\"") && html.contains(":settings\""))
    #expect(html.contains("data-list-row-hover-effect=\"lift\""))
    #expect(html.contains("data-list-row-hover-disabled=\"true\""))
    #expect(html.contains("data-hover-enabled=\"false\""))
    #expect(html.contains(":named\""))
    #expect(html.contains("data-hover-group-root=\"implicit:"))
  }

  @Test
  func frameFragmentDisabledControlsAndCustomShapeModifiersPreserveSemantics() throws {
    let grouped = FiberTree(
      Group {
        Text("First grouped row")
        Text("Second grouped row")
      }
      .padding(2)
    )
    let paddingOccurrences = grouped.renderNode.htmlDescription.components(separatedBy: "padding: 2px").count - 1
    #expect(paddingOccurrences == 2)

    let leadingFrame = FiberTree(VStack { Text("Leading") }.frame(width: 120, height: 80, alignment: .leading))
    let topFrame = FiberTree(VStack { Text("Top") }.frame(width: 120, height: 80, alignment: .top))
    #expect(leadingFrame.renderNode.htmlDescription.contains("margin-right: auto"))
    #expect(topFrame.renderNode.htmlDescription.contains("margin-bottom: auto"))

    let disabledLink = FiberTree(Link("Unavailable", destination: URL(string: "/unavailable")!).disabled(true))
    let link = try #require(findNode(disabledLink.renderNode) { $0.attributes["data-control-kind"] == "link" })
    #expect(link.attributes["href"] == nil)
    #expect(link.attributes["tabindex"] == "-1")
    #expect(link.events["click"]?.preventsDefault == true)

    final class SearchValue { var text = "settings" }
    let value = SearchValue()
    let search = FiberTree(
      Text("Results")
        .searchable(text: Binding(get: { value.text }, set: { value.text = $0 }), prompt: "Find")
        .disabled(true)
    )
    let field = try #require(findNode(search.renderNode) { $0.attributes["type"] == "search" })
    #expect(field.attributes["disabled"] == "disabled")
    #expect(field.attributes["aria-disabled"] == "true")
    #expect(field.events["input"] == nil)

    let disabledTag = FiberTree(Text("Disabled tag").tag("disabled-value").disabled(true))
    let taggedNode = try #require(findNode(disabledTag.renderNode) {
      $0.attributes["data-tag"] != nil
    })
    #expect(taggedNode.attributes["disabled"] == "disabled")
    #expect(taggedNode.attributes["aria-disabled"] == "true")

    let contentShape = FiberTree(Text("Custom hit area").contentShape(ContractCustomShape()))
    let shapedText = try #require(findNode(contentShape.renderNode) { $0.text == "Custom hit area" })
    #expect(shapedText.attributes["data-content-shape"] != nil)
    #expect(shapedText.attributes["data-content-shape-path"] != nil)
    #expect(shapedText.styles["clip-path"]?.hasPrefix("path('") == true)

    let solidForeground = FiberTree(
      Text("Solid color").foregroundStyle(AnyShapeStyle(Color.blue))
    ).renderNode
    #expect(solidForeground.styles["color"] == Color.blue.cssValue)

    let customStroke = FiberTree(ContractCustomShape().strokeBorder(Color.red, lineWidth: 3))
    #expect(customStroke.renderNode.attributes["data-shape-stroke-border"] == "true")
    let customShape = ContractCustomShape()
    let bounds = CGRect(x: 3, y: 4, width: 20, height: 12)
    let trimmed = customShape.trim(from: -1, to: 2)
    #expect(trimmed.from == 0 && trimmed.to == 1)
    #expect(trimmed.path(in: bounds) == customShape.path(in: bounds))

    let meshBackground = FiberTree(
      Text("Mesh-backed shape")
        .background(MeshGradient(width: 1, height: 1, points: [.init(0, 0)], colors: [.purple]), in: Circle())
    )
    #expect(meshBackground.renderNode.htmlDescription.contains("data-background-mesh-gradient=\"true\""))
  }

  private func findNode(_ node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> _RenderNode? {
    if predicate(node) { return node }
    for child in node.children {
      if let match = findNode(child, where: predicate) { return match }
    }
    return nil
  }
}
