import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebHTML
@_spi(Renderer) import SwiftUIWebFiber

/// The web hover modifiers only describe the two values; the stylesheet does
/// the rest. They must stay a pure description (no events, no state).
@Suite
@MainActor
struct WebHoverTests {
  private func html<V: View>(_ view: V) -> String {
    StaticHTMLFiberRenderer().renderNode(FiberTree(view, deferLazyCollections: false, startLifecycle: false).renderNode)
  }

  @Test
  func backgroundAndForegroundRecordBothValuesAndRegisterNoPointerEvents() {
    let markup = html(Text("x").webHoverBackground(Color("#111111"), hover: Color("#222222")).webHoverForeground(Color("#333333"), hover: Color("#444444")))
    #expect(markup.contains("data-hover-bg"))
    #expect(markup.contains("data-hover-fg"))
    #expect(markup.contains("--hover-bg-base: #111111"))
    #expect(markup.contains("--hover-bg: #222222"))
    #expect(markup.contains("--hover-fg-base: #333333"))
    #expect(markup.contains("--hover-fg: #444444"))
    // Hovering must never reach Swift: no enter/leave listeners are emitted.
    #expect(!markup.contains("mouseenter"))
    #expect(!markup.contains("mouseleave"))
  }

  @Test
  func shadowUnderlineAndLiftMarkTheirElements() {
    let shadowed = html(Text("x").webHoverShadow(Color("#000000"), radius: 14, y: 8))
    #expect(shadowed.contains("data-hover-shadow"))
    #expect(shadowed.contains("--hover-shadow-blur: 28px"))
    #expect(shadowed.contains("--hover-shadow-y: 8px"))
    #expect(html(Text("x").webHoverUnderline()).contains("data-hover-underline"))
    let card = html(VStack { Text("poster").webLiftedByHover(shadow: Color("#000000")) }.webHoverLiftsChildren())
    #expect(card.contains("data-hover-lifts"))
    #expect(card.contains("data-lift-target"))
  }

  @Test
  func strokeColorFollowsTheHoverVariableWithAFallback() {
    #expect(Color.webHoverStroke(fallback: Color("#abcdef")).cssValue == "var(--hover-stroke, #abcdef)")
    let markup = html(Text("x").webHoverStroke(base: Color("#111111"), hover: Color("#222222")))
    #expect(markup.contains("data-hover-stroke"))
    #expect(markup.contains("--hover-stroke-base: #111111"))
    #expect(markup.contains("--hover-stroke-hover: #222222"))
  }
}
