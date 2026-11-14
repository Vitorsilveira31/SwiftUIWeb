import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Browser) @_spi(Renderer) @testable import SwiftUIWebBrowser

@MainActor
struct CSSLayoutEmitterPriorityTests {
  /// The emitter's rules for an HStack of two flexible views, the first at `priority`; nil when CSS does not lay it out.
  private func rules(priority: Double) -> String? {
    let tree = FiberTree(
      HStack(spacing: 0) {
        Color.red.frame(maxWidth: .infinity).layoutPriority(priority)
        Color.blue.frame(maxWidth: .infinity)
      },
      deferLazyCollections: false)
    defer { tree._dispose() }
    let emitter = _CSSLayoutEmitter()
    emitter.enabled = true
    emitter.run(tree.root)
    return emitter.roots.isEmpty ? nil : emitter.resolvedRules()
  }

  /// `Math.pow(1e6, priority + 1)` of the JS mapper (`weight`), which the browser parity suite compares with the page's
  /// analysis block for block (`EmbeddedLayerFixture`): whole and half priorities are exact.
  @Test(arguments: [(-1.0, "1"), (-0.5, "1000"), (0.0, "1000000"), (0.5, "1000000000"), (1.0, "1000000000000"), (2.5, "1e+21"), (3.0, "1e+24"), (7.0, "1e+24")])
  func writesTheFlexTierOfAWholeOrHalfPriority(priority: Double, grow: String) {
    guard let rules = rules(priority: priority) else { Issue.record("priority \(priority) is refused"); return }
    #expect(rules.contains("flex:\(grow) 1 0%"), "the first view grows by \(grow)")
  }

  /// Another fraction is rounded by `Math.pow` differently in each engine, so the page lays it out.
  @Test
  func refusesAPriorityWhoseTierIsNotExact() {
    #expect(rules(priority: 0.25) == nil)
  }
}

@MainActor
struct CSSLayoutEmitterCellRootTests {
  /// The emitter's rules for a sheet whose content is `content`; nil when CSS does not lay it out.
  private func sheetRules<Content: View>(@ViewBuilder _ content: () -> Content) -> String? {
    let sheet = content()
    let tree = FiberTree(
      Text("Root").sheet(isPresented: .constant(true)) { sheet },
      deferLazyCollections: false)
    defer { tree._dispose() }
    let emitter = _CSSLayoutEmitter()
    emitter.enabled = true
    emitter.run(tree.root)
    return emitter.roots.isEmpty ? nil : emitter.resolvedRules()
  }

  /// A root in a one-cell grid (a sheet's content, a pane of a split view in the page's mapper) with a finite maximum takes
  /// `min(offered, maximum)` and keeps its minimum, as the JS mapper's `rootPlacement` writes it (the browser parity suite
  /// compares the two block for block).
  @Test
  func aFiniteMaximumAndAMinimumAreWrittenInTheCell() {
    guard let rules = sheetRules({ Text("Hi").frame(minWidth: 120, maxWidth: 220) }) else { Issue.record("the sheet is refused"); return }
    #expect(rules.contains("width:220px!important;max-width:100%!important"), "the width is the maximum, capped by the cell")
    #expect(rules.contains("min-width:120px!important"), "the minimum is kept")
  }
}
