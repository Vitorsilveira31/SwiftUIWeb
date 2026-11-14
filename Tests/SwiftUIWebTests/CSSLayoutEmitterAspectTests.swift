import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Browser) @_spi(Renderer) @testable import SwiftUIWebBrowser

@MainActor
struct CSSLayoutEmitterAspectTests {
  /// The declarations the emitter writes for the aspect box of `content` (the rule that holds its `aspect-ratio`); nil when CSS does not lay it out.
  private func aspectBlock<V: View>(_ content: V) -> String? {
    let tree = FiberTree(content, deferLazyCollections: false)
    defer { tree._dispose() }
    let emitter = _CSSLayoutEmitter()
    emitter.enabled = true
    emitter.run(tree.root)
    guard !emitter.roots.isEmpty else { return nil }
    return emitter.resolvedRules().split(separator: "\n").first { $0.contains("aspect-ratio:") }.map(String.init)
  }

  /// The `max-width` that wins in `block` (the last one declared), without its `!important`.
  private func maxWidth(_ block: String?) -> String? {
    guard let range = block?.range(of: "max-width:", options: .backwards), let block else { return nil }
    return String(block[range.upperBound...].prefix { $0 != "!" && $0 != ";" && $0 != "}" })
  }

  /// SwiftUI proposes a frame's own height to what it holds: `.aspectRatio(2, .fit)` in `.frame(maxHeight: 80)` is 80 tall, so 160 wide
  /// (Apple's `x-frame-max-hug.aspect`), where a width and the ratio alone would make it overflow the frame.
  @Test
  func capsTheBoxByTheHeightItsFrameProposes() {
    #expect(maxWidth(aspectBlock(Color.green.aspectRatio(2, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 80))) == "160px")
  }

  @Test
  func capsTheBoxByATallRatioAndAFixedHeight() {
    #expect(maxWidth(aspectBlock(Color.green.aspectRatio(0.5, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 80))) == "40px")
    #expect(maxWidth(aspectBlock(Color.green.aspectRatio(2, contentMode: .fit).frame(height: 50))) == "100px")
  }

  /// A padding inside the frame takes its insets from what the frame proposes (Apple's `x-aspect-cap-padded.aspect`: 120 x 60).
  @Test
  func subtractsThePaddingBetweenTheBoxAndTheFrame() {
    #expect(maxWidth(aspectBlock(Color.green.aspectRatio(2, contentMode: .fit).padding(10).frame(maxWidth: .infinity, maxHeight: 80))) == "120px")
  }

  /// No finite height is proposed (no frame, a frame that only has a width), or the box fills it: nothing caps the box.
  @Test
  func leavesAnUncappedBoxAlone() {
    #expect(maxWidth(aspectBlock(Color.green.aspectRatio(2, contentMode: .fit))) != "160px")
    for block in [aspectBlock(Color.green.aspectRatio(2, contentMode: .fit)), aspectBlock(Color.green.aspectRatio(2, contentMode: .fit).frame(maxWidth: .infinity)),
                  aspectBlock(Color.green.aspectRatio(2, contentMode: .fill).frame(maxWidth: .infinity, maxHeight: 80))] {
      #expect(block != nil && maxWidth(block)?.hasSuffix("px") != true, "\(block ?? "refused")")
    }
  }
}
