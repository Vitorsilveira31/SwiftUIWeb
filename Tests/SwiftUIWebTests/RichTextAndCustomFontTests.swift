import Testing
import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
struct RichTextAndCustomFontTests {
  @Test
  func textReturningModifiersKeepAnOrdinaryTextLeaf() {
    // The explicit `Text` annotation is the source-compatibility contract:
    // these modifiers must return Text (as on Apple platforms), not a
    // ModifiedContent, so the result can take part in concatenation.
    let styled: Text = Text("Bold")
      .bold()
      .italic()
      .fontWeight(.semibold)
      .foregroundColor(Color("#123456"))
      .underline()
      .kerning(1.5)
      .monospacedDigit()
    let node = styled._render(in: _RenderContext())
    #expect(node.kind == .text)
    #expect(node.text == "Bold")
    #expect(node.styles["font-weight"] == "600")
    #expect(node.styles["font-style"] == "italic")
    #expect(node.styles["color"] == "#123456")
    #expect(node.styles["text-decoration-line"] == "underline")
    #expect(node.styles["letter-spacing"] == "1.5px")
    #expect(node.styles["font-variant-numeric"] == "tabular-nums")

    let plain = StaticHTMLFiberRenderer().render(Text("Plain").bold())
    #expect(plain.contains("<span style=\"font-weight: 700;\">Plain</span>"))
  }

  @Test
  func concatenationRendersOneParagraphLeafWithInlineRuns() throws {
    let summary = Text("8 tasks need you").fontWeight(.semibold).foregroundColor(Color("#111111"))
      + Text(" and ")
      + Text("1 job is").bold()
      + Text(" running.")
    #expect(summary.value == "8 tasks need you and 1 job is running.")

    let tree = FiberTree(summary.font(.custom("Figtree", size: 14)).lineLimit(2).multilineTextAlignment(.center))
    let leaf = try #require(findNode(tree.renderNode) { $0.attributes["data-layout-leaf"] == "text" })
    #expect(leaf.kind == .element("span"))
    #expect(leaf.classes == ["rich-text-run"])
    #expect(leaf.attributes["data-layout-kind"] == "intrinsic")
    #expect(leaf.styles["-webkit-line-clamp"] == "2")
    #expect(leaf.styles["text-align"] == "center")
    #expect(leaf.styles["font-size"] == "14px")
    #expect(leaf.children.map { $0.text ?? "" } == ["8 tasks need you", " and ", "1 job is", " running."])
    #expect(leaf.children[0].styles["font-weight"] == "600")
    #expect(leaf.children[0].styles["color"] == "#111111")
    #expect(leaf.children[1].styles.isEmpty)
    #expect(leaf.children[2].styles["font-weight"] == "700")
    // Runs are inline content of the one leaf, never independent layout leaves.
    #expect(leaf.children.allSatisfy { $0.attributes["data-layout-leaf"] == nil })
  }

  @Test
  func concatenationFlattensPlainGroupsAndNestsStyledGroups() throws {
    let flat = (Text("a") + Text("b")) + (Text("c") + Text("d"))
    #expect(flat._textRuns.count == 4)

    let nested = Text("x") + (Text("y") + Text("z")).italic()
    #expect(nested._textRuns.count == 2)
    let tree = FiberTree(nested)
    let leaf = try #require(findNode(tree.renderNode) { $0.attributes["data-layout-leaf"] == "text" })
    let group = try #require(leaf.children.last)
    #expect(group.kind == .element("span"))
    #expect(group.styles["font-style"] == "italic")
    #expect(group.attributes["data-layout-leaf"] == nil)
    #expect(StaticHTMLFiberRenderer().render(nested).contains("x<span class=\"rich-text-run\" style=\"font-style: italic;\">yz</span>"))
  }

  @Test
  func interpolatedImagesSplitTheLineIntoImageRuns() {
    // `appendInterpolation(_: Image)` leaves markers; expansion turns each into its own run, so the words around it stay text.
    let line = Text("Ver \(Image("star")) agora")
    #expect(line._textRuns.count == 3)
    #expect(line._textRuns[0].value == "Ver ")
    #expect(line._textRuns[1]._inlineImage?.source == "star")
    #expect(line._textRuns[1]._inlineImage?.alt == "")
    #expect(line._textRuns[2].value == " agora")
    // A symbol image is drawn as its glyph, not as an `<img>`.
    let symbol = Text("\(Image(systemName: "star.fill"))")
    #expect(symbol._inlineImage == nil)
    #expect(!symbol.value.isEmpty)
  }

  @Test
  func richTextKeepsItsAccessibleStringInLabels() throws {
    let tree = FiberTree(Toggle(isOn: .constant(true)) { Text("Notify ") + Text("me").bold() })
    let input = try #require(findNode(tree.renderNode) { $0.attributes["role"] == "switch" })
    #expect(input.attributes["aria-label"] == "Notify me")
    let accessible = Text("Open").bold() + Text(" reviews")
    #expect(StaticHTMLFiberRenderer().render(Color.clear.accessibilityLabel(accessible)).contains("Open reviews"))
    // Same overload resolution as the View modifiers for shape styles.
    let secondary: Text = Text("Muted").foregroundStyle(.secondary)
    #expect(secondary._render(in: _RenderContext()).styles["color"] != nil)
  }

  @Test
  func customFontsEmitAnOverridableFamilyStackAndChainTraits() {
    let font = Font.custom("Newsreader", size: 34).weight(.medium).italic().monospacedDigit()
    #expect(font.cssStyles["font-family"]
      == "var(--asset-font-newsreader, \"Newsreader\", system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif)")
    #expect(font.cssStyles["font-size"] == "34px")
    #expect(font.cssStyles["line-height"] == "normal")
    #expect(font.cssStyles["font-weight"] == "500")
    #expect(font.cssStyles["font-style"] == "italic")
    #expect(font.cssStyles["font-variant-numeric"] == "tabular-nums")

    let relative = Font.custom("SF Pro \"Display\"", size: 14.5, relativeTo: .headline)
    #expect(relative.cssStyles["font-family"]?.hasPrefix("var(--asset-font-sf-pro-display, \"SF Pro Display\", ") == true)
    #expect(relative.cssStyles["font-size"] == "14.5px")
    #expect(Font.custom("Figtree", fixedSize: 12).cssStyles["font-size"] == "12px")

    let html = StaticHTMLFiberRenderer().render(Text("Title").font(.custom("Figtree", size: 19)).fontWeight(.bold))
    #expect(html.contains("font-family: var(--asset-font-figtree, &quot;Figtree&quot;"))
    #expect(html.contains("font-weight: 700;"))
  }
}

private func findNode(_ node: _RenderNode, matching predicate: (_RenderNode) -> Bool) -> _RenderNode? {
  if predicate(node) { return node }
  for child in node.children {
    if let match = findNode(child, matching: predicate) { return match }
  }
  return nil
}
