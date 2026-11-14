import Testing
import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// `.shadow` shadows what the view draws, as in SwiftUI: a text's glyphs, a shape's or a
/// container's box.
@Suite
@MainActor
struct ShadowRenderingTests {
  @Test func text_casts_a_text_shadow() {
    let node = Text("Preview").font(.headline).shadow(color: .black, radius: 3, x: 0, y: 2)._render(in: _RenderContext())
    var styles: [String: String] = [:]
    node._forEachHost { styles.merge($0.styles) { $1 } }
    #expect(styles["text-shadow"] != nil)
    #expect(styles["box-shadow"] == nil, "no box around the words")
  }

  @Test func a_container_keeps_its_box_shadow() {
    let node = VStack { Text("A") }.shadow(color: .black, radius: 3)._render(in: _RenderContext())
    var styles: [String: String] = [:]
    node._forEachHost { styles.merge($0.styles) { $1 } }
    #expect(styles["box-shadow"] != nil)
  }
}
