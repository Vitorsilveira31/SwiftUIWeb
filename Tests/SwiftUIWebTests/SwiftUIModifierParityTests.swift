import Testing
import Foundation
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
import SwiftUIWebHTML
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// SwiftUI-spelled accessibility, layout and everyday modifiers. The call
/// sites use Apple's exact labels and overload shapes.
@Suite
@MainActor
struct SwiftUIModifierParityTests {
  private func html<V: View>(_ view: V) -> String { StaticHTMLFiberRenderer().render(view) }
  private func node<V: View>(_ view: V) -> _RenderNode { FiberTree(view).renderNode }

  @Test
  func accessibilityElementCombineJoinsChildLabelsAndHidesStaticChildren() {
    let combined = node(HStack { Text("Rating"); Text("4 stars") }.accessibilityElement(children: .combine))
    #expect(combined.attributes["role"] == "group")
    #expect(combined.attributes["aria-label"] == "Rating, 4 stars")
    #expect(combined.attributes["data-a11y-children"] == "combine")
    let markup = html(HStack { Text("Rating"); Text("4 stars") }.accessibilityElement(children: .combine))
    #expect(markup.components(separatedBy: "aria-hidden=\"true\"").count == 3)
  }

  @Test
  func accessibilityElementIgnoreKeepsOnlyItsOwnLabelButNeverHidesControls() {
    let ignored = node(
      HStack { Text("Decorative"); Button("Act") {} }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Summary")
    )
    #expect(ignored.attributes["aria-label"] == "Summary")
    let markup = html(HStack { Text("Decorative"); Button("Act") {} }.accessibilityElement(children: .ignore))
    #expect(markup.contains("aria-hidden=\"true\""))
    #expect(markup.components(separatedBy: "aria-hidden=\"true\"").count == 2)
    #expect(!markup.contains("<button aria-hidden"))
    // The default behavior is `.ignore`, as in SwiftUI.
    #expect(node(Text("x").accessibilityElement()).attributes["data-a11y-children"] == "ignore")
  }

  @Test
  func accessibilityElementContainIsAGroupWithReachableChildren() {
    let contained = node(VStack { Text("Inside") }.accessibilityElement(children: .contain).accessibilityLabel("Group"))
    #expect(contained.attributes["role"] == "group")
    #expect(contained.attributes["aria-label"] == "Group")
    #expect(!html(VStack { Text("Inside") }.accessibilityElement(children: .contain)).contains("aria-hidden"))
    // A native button keeps its own role.
    #expect(node(Button("B") {}.accessibilityElement(children: .combine)).attributes["role"] != "group")
  }

  @Test
  func containedScrollViewIsAFocusableNamedRegion() {
    // A wide table that scrolls sideways: readers list the region by name
    // and the keyboard reaches it, so the table can be scrolled without a
    // pointer. Combining and ignoring keep the grouping role.
    let region = node(
      ScrollView(.horizontal) { Text("Wide table") }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table, scroll sideways when needed")
        .focusable()
    )
    #expect(region.attributes["role"] == "region")
    #expect(region.attributes["aria-label"] == "Table, scroll sideways when needed")
    #expect(region.attributes["tabindex"] == "0")
    #expect(region.attributes["data-scroll-node"] == "true")
    #expect(!html(ScrollView(.horizontal) { Text("Wide table") }.accessibilityElement(children: .contain)).contains("aria-hidden"))
    #expect(node(ScrollView { Text("x") }.accessibilityElement(children: .combine)).attributes["role"] == "group")
    #expect(node(VStack { Text("x") }.accessibilityElement(children: .contain)).attributes["role"] == "group")
  }

  @Test
  func containerRelativeFrameDescribesSwiftUILengthFunctions() {
    let counted = node(Color.teal.containerRelativeFrame(.horizontal, count: 3, span: 2, spacing: 10))
    #expect(counted.attributes["data-layout-kind"] == "container-relative")
    // ((c - 20) / 3) * 2 + 10 evaluated at 0 and 1000.
    let samples = counted.attributes["data-relative-w"] ?? ""
    #expect(samples.hasPrefix("0.0:-3.33333"))
    #expect(samples.contains("1000.0:663.33333"))
    #expect(counted.attributes["data-relative-h"] == nil)

    let full = node(Color.teal.containerRelativeFrame([.horizontal, .vertical], alignment: .topLeading))
    #expect(full.attributes["data-relative-w"] == "0.0:0.0;1000.0:1000.0")
    #expect(full.attributes["data-relative-h"] == "0.0:0.0;1000.0:1000.0")
    #expect(full.attributes["data-align-x"] == "0" && full.attributes["data-align-y"] == "0")

    let closure = node(Color.teal.containerRelativeFrame(.vertical) { length, axis in
      axis == .vertical ? min(length * 0.5, 300) : length
    })
    let vertical = closure.attributes["data-relative-h"] ?? ""
    #expect(vertical.contains("320.0:160.0"))
    #expect(vertical.contains("1024.0:300.0"))
  }

  @Test
  func positionAndOffsetUseSwiftUISemantics() {
    let positioned = node(Circle().frame(width: 10, height: 10).position(x: 30, y: 20))
    #expect(positioned.attributes["data-layout-kind"] == "position")
    #expect(positioned.attributes["data-position-x"] == "30.0")
    #expect(positioned.attributes["data-position-y"] == "20.0")
    #expect(node(Text("p").position(CGPoint(x: 1, y: 2))).attributes["data-position-y"] == "2.0")
    #expect(html(Text("o").offset(CGSize(width: 3, height: 4))).contains("translate(3px, 4px)"))
  }

  @Test
  func labelStylesResolveBuiltInsAndCustomStyles() {
    let iconOnly = node(Label("Settings", systemImage: "gear").labelStyle(.iconOnly))
    #expect(iconOnly.attributes["aria-label"] == "Settings")
    #expect(iconOnly.children.count == 1)
    #expect(iconOnly.children.first?.attributes["data-symbol"] == "gear")
    let titleOnly = node(Label("Title", systemImage: "star").labelStyle(.titleOnly))
    #expect(titleOnly.children.count == 1 && titleOnly.children.first?.text == "Title")
    #expect(node(Label("Both", systemImage: "star").labelStyle(.titleAndIcon)).children.count == 2)
    // Styles are inherited through the environment, like SwiftUI.
    #expect(html(VStack { Label("Inherited", systemImage: "star") }.labelStyle(.iconOnly)).contains("data-label-style=\"icon-only\""))
    #expect(html(Label("Custom", systemImage: "star").labelStyle(BadgeLabelStyle())).contains("data-custom-label=\"true\""))
  }

  @Test
  func contextMenuKeepsItemsInAHiddenMenuPanelBesideTheContent() {
    var chosen = ""
    let root = node(Text("Row").contextMenu {
      Button("Copy") { chosen = "copy" }
      Divider()
    })
    #expect(root.attributes["data-context-menu"] == "true")
    #expect(root.attributes["data-layout-kind"] == "zstack")
    let panel = root.children.last
    #expect(panel?.classes == ["context-menu-panel"])
    #expect(panel?.attributes["role"] == "menu")
    #expect(panel?.attributes["popover"] == "manual")
    #expect(root.children.first?.text == "Row")
    #expect(chosen.isEmpty)
    let empty = node(Text("Row").contextMenu(menuItems: { EmptyView() }, preview: { Text("Preview") }))
    #expect(empty.attributes["data-context-menu"] == nil)
  }

  @Test
  func controlGroupIsANamedGroupOfControls() {
    let group = node(ControlGroup("Edit") { Button("Undo") {}; Button("Redo") {} })
    #expect(group.attributes["role"] == "group")
    #expect(group.attributes["aria-label"] == "Edit")
    #expect(group.classes.contains("control-group"))
    #expect(node(ControlGroup { Button("A") {} }).attributes["aria-label"] == nil)
  }

  @Test
  func everydayTextAndSymbolModifiersMapToBrowserPrimitives() {
    #expect(html(Text("t").lineLimit(1).truncationMode(.tail)).contains("text-overflow: ellipsis"))
    #expect(html(Text("t").truncationMode(.head)).contains("direction: rtl"))
    #expect(html(Text("t").textSelection(.enabled)).contains("user-select: text"))
    #expect(html(Text("t").textSelection(.disabled)).contains("user-select: none"))
    #expect(html(Text("t").fontWidth(.condensed)).contains("font-stretch: 87.5%"))
    #expect(html(Image(systemName: "star").imageScale(.large)).contains("--image-scale: 1.29"))
    #expect(html(Button("i") {}.help("Explains")).contains("title=\"Explains\""))
    #expect(html(Image(systemName: "star").symbolRenderingMode(.hierarchical).symbolVariant(.fill)).contains("data-symbol-variant=\"fill\""))
    #expect(html(Text("t").sensoryFeedback(.success, trigger: 1)).contains("data-sensory-feedback=\"success\""))
    #expect(html(Text("t").privacySensitive()).contains("data-privacy-sensitive=\"true\""))
    #expect(html(Text("t").allowsTightening(true)).contains("data-allows-tightening=\"true\""))
    #expect(html(Text("t").containerShape(RoundedRectangle(cornerRadius: 8))).contains("data-container-shape"))
  }

  @Test
  func contentUnavailableViewSymbolEffectsAndHierarchicalStylesUseSwiftUISpellings() {
    let empty = html(ContentUnavailableView("No Items", systemImage: "tray", description: Text("Add one to begin")))
    #expect(empty.contains("data-symbol=\"tray\""))
    #expect(empty.contains("No Items") && empty.contains("Add one to begin"))
    #expect(html(ContentUnavailableView("Plain", systemImage: "tray")).contains("content-unavailable-icon"))
    #expect(html(Image(systemName: "wifi").symbolEffect(.pulse, isActive: true)).contains("data-symbol-effect-active=\"true\""))
    #expect(html(Image(systemName: "bell").symbolEffect(.bounce, value: 3)).contains("data-symbol-effect=\"bounce\""))
    #expect(html(Image(systemName: "bell").symbolEffect(.variableColor.iterative, options: .repeating, isActive: false)).contains("data-symbol-effect=\"variable-color\""))
    #expect(html(Text("3").contentTransition(.numericText(value: 3))).contains("data-content-transition=\"numeric-text\""))
    let styled = html(Label("Hi", systemImage: "star").foregroundStyle(.blue, .gray))
    #expect(styled.contains("color: \(Color.blue.cssValue)") && styled.contains("--secondary-style: \(Color.gray.cssValue)"))
  }

  @Test
  func scrollTargetBehaviorEmitsTheHostSnapTokens() {
    #expect(html(ScrollView { Text("a") }.scrollTargetBehavior(.viewAligned)).contains("data-scroll-target-behavior=\"view-aligned\""))
    #expect(html(ScrollView { Text("a") }.scrollTargetBehavior(.paging)).contains("data-scroll-target-behavior=\"paging\""))
  }

  @Test
  func scaledMetricFollowsTheEnvironmentDynamicTypeSize() {
    struct Probe: View {
      @ScaledMetric var size: Double = 17
      @ScaledMetric(relativeTo: .title) var title: Double = 10
      var body: some View { Text("size \(Int(size.rounded())) \(Int(title.rounded()))") }
    }
    #expect(html(Probe()).contains("size 17 10"))
    #expect(html(Probe().dynamicTypeSize(.accessibility1)).contains("size 28 16"))
    #expect(html(Probe().dynamicTypeSize(.xSmall)).contains("size 14 8"))
  }
}

private struct BadgeLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack { configuration.title; configuration.icon }.accessibilityIdentifier("custom").accessibilityHint("h").modifier(CustomLabelMarker())
  }
}

private struct CustomLabelMarker: ViewModifier {
  func _apply(to node: _RenderNode, context: inout _RenderContext) { node.attributes["data-custom-label"] = "true" }
}
